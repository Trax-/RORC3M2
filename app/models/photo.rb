class Photo
  attr_accessor :id, :location
  attr_writer :contents

  def initialize(params=nil)
    unless params.nil?
      @id = params[:_id].nil? ? nil : params[:_id].to_s
      @location = params[:metadata].nil? ? nil : Point.new(params[:metadata][:location])
      @place = params[:metadata].nil? ? nil : params[:metadata][:place]
    end
  end

  def place
    unless @place.nil?
      Place.find(@place.to_s)
    end
  end

  def place=(p)
    if p.is_a? String
      @place = BSON::ObjectId.from_string(p)
    else
      @place=p
    end
  end

  def self.mongo_client
    Mongoid::Clients.default
  end

  def persisted?
    !@id.nil?
  end

  def save

    @place = BSON::ObjectId.from_string(@place.id) if @place.is_a? Place

    if persisted?
      image = self.class.mongo_client.database.fs.find('_id': BSON::ObjectId.from_string(@id)).first
      image[:metadata][:location] = @location.to_hash
      image[:metadata][:place] = @place
      self.class.mongo_client.database.fs.find('_id': BSON::ObjectId.from_string(@id)).update_one(image)
    else
      gps = EXIFR::JPEG.new(@contents).gps
      location = Point.new('lng': gps.longitude, 'lat': gps.latitude)

      @contents.rewind
      description = {}
      description[:content_type] = 'image/jpeg'
      description[:metadata] = {location: location.to_hash, place: @place}

      @location = Point.new(location.to_hash)
      grid_file = Mongo::Grid::File.new(@contents.read, description)

      @id = self.class.mongo_client.database.fs.insert_one(grid_file).to_s
    end
  end

  def self.all(offset=0, limit=0)
    self.mongo_client.database.fs.find.skip(offset).limit(limit).map { |doc| Photo.new(doc) }
  end

  def self.find(id)
    found = self.mongo_client.database.fs.find('_id': BSON::ObjectId.from_string(id)).first
    found.nil? ? nil : Photo.new(found)
  end

  def contents
    c = self.class.mongo_client.database.fs.find_one('_id': BSON::ObjectId.from_string(@id))
    if c
      buffer = ''
      c.chunks.reduce([]) { |x, chunk| buffer << chunk.data.data }
      return buffer
    end
  end

  def destroy
    self.class.mongo_client.database.fs.find('_id': BSON::ObjectId.from_string(@id)).delete_one
  end

  def find_nearest_place_id(max_meters)
    Place.near(@location, max_meters).limit(1).projection({_id: 1}).first[:_id]
  end

  def self.find_photos_for_place(place_id)
    place_id = place_id.is_a?(String) ? BSON::ObjectId.from_string(place_id) : place_id
    mongo_client.database.fs.find('metadata.place': place_id)
  end
end
