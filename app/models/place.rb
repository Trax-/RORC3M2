class Place
  include ActiveModel::Model

  attr_accessor :id, :formatted_address, :location, :address_components

  def persisted?
    !@id.nil?
  end

  def initialize(params)
    @id = params[:_id].to_s

    @address_components = []
    unless params[:address_components].nil?
      params[:address_components].each { |ac| @address_components << AddressComponent.new(ac) }
    end

    @formatted_address = params[:formatted_address]
    @location = Point.new(params[:geometry][:geolocation])
  end

  def self.mongo_client
    Mongoid::Clients.default
  end

  def self.collection
    self.mongo_client['places']
  end

  def self.load_all(handle)
    self.collection.insert_many(JSON.parse(File.read(handle)))
  end

  def self.find_by_short_name(name)
    self.collection.find({'address_components.short_name': name})
  end

  def self.to_places(parm)
    result = []
    parm.each { |i| result << Place.new(i) }
    return result
  end

  def self.find(id)
    doc = self.collection.find(_id: BSON::ObjectId.from_string(id)).first
    return doc.nil? ? nil : Place.new(doc)
  end

  def self.all(offset=0, limit=nil)
    if limit.nil?
      self.collection.find.skip(offset).map { |m| Place.new(m) }
    else
      self.collection.find.skip(offset).limit(limit).map { |m| Place.new(m) }
    end
  end

  def destroy
    self.class.collection.find(_id: BSON::ObjectId.from_string(@id)).delete_one
  end

  def self.get_address_components(sort=nil, offset=0, limit=nil)
    if limit.nil?
      self.collection.find.aggregate(
          [
              {'$unwind': '$address_components'},
              {'$project': {address_components: 1, formatted_address: 1, geometry: {geolocation: 1}}},
              {'$sort': sort.nil? ? {_id: 1} : sort},
              {'$skip': offset}
          ]
      )
    else
      self.collection.find.aggregate(
          [
              {'$unwind': '$address_components'},
              {'$project': {address_components: 1, formatted_address: 1, geometry: {geolocation: 1}}},
              {'$sort': sort.nil? ? {_id: 1} : sort},
              {'$skip': offset},
              {'$limit': limit}
          ]
      )
    end
  end

  def self.get_country_names
    self.collection.find.aggregate(
        [
            {'$unwind': '$address_components'},
            {'$project': {_id: 0, address_components: {long_name: 1, types: 1}}},
            {'$match': {'address_components.types': 'country'}},
            {'$group': {_id: '$address_components.long_name'}}
        ]
    ).to_a.map { |h| h[:_id] }
  end

  def self.find_ids_by_country_code(country_code)
    self.collection.find.aggregate(
        [
            {'$match': {'address_components.short_name': country_code}},
            {'$project': {_id: 1}}
        ]
    ).map { |doc| doc[:_id].to_s }
  end

  def self.create_indexes
    self.collection.indexes.create_one(
        {'geometry.geolocation': Mongo::Index::GEO2DSPHERE}
    )
  end

  def self.remove_indexes
    self.collection.indexes.drop_one('geometry.geolocation_2dsphere')
  end

  def self.near(point, max_meters=nil)
    max_meters = max_meters.to_i unless max_meters.nil?
    self.collection.find(
        {'geometry.geolocation':
             {'$near': point.to_hash, '$maxDistance': max_meters}}
    )
  end

  def near(max_meters=nil)
    self.class.to_places(self.class.near(@location, max_meters))
  end

  def photos(offset=0, limit=nil)
    if limit.nil?
      self.class.mongo_client.database.fs
          .find('metadata.place': BSON::ObjectId.from_string(@id))
          .skip(offset)
          .map { |photo| Photo.new(photo) }
    else
      self.class.mongo_client.database.fs
          .find('metatdata.place': BSON::ObjectId.from_string(@id))
          .skip(offset)
          .limit(limit)
          .map { |photo| Photo.new(photo) }
    end
  end
end