class CuriosityScraper
  require "open-uri"
  require 'json'

  # Use the official API URL structure
  BASE_URL = "https://api.nasa.gov/mars-photos/api/v1/rovers/curiosity/photos"

  attr_reader :rover, :api_key

  def initialize
    @rover = Rover.find_by(name: "Curiosity")
    # Grab key from ENV, fallback to DEMO_KEY
    @api_key = ENV['NASA_API_KEY'] || 'DEMO_KEY'
  end

  def scrape
    collect_and_save_photos
  end

  # Helper to open URLs with error handling
  def open_url(url)
    puts "📡 Fetching: #{url}"
    URI.open(url).read
  rescue OpenURI::HTTPError => e
    puts "❌ HTTP Error: #{e.message} (Likely rate limit or invalid key)"
    return nil
  end

  def collect_and_save_photos
    # 1. Find out the latest Sol from NASA's manifest
    manifest_url = "https://api.nasa.gov/mars-photos/api/v1/manifests/curiosity?api_key=#{@api_key}"
    json_data = open_url(manifest_url)
    return if json_data.nil?

    manifest = JSON.parse(json_data)
    max_sol = manifest["photo_manifest"]["max_sol"].to_i

    # 2. Check where we left off in our DB
    latest_sol_scraped = rover.photos.maximum(:sol).to_i || 0
    start_sol = latest_sol_scraped + 1

    # 3. Limit to 50 Sols at a time to be safe
    end_sol = [start_sol + 50, max_sol].min

    puts "📊 Status: DB Sol: #{latest_sol_scraped} | NASA Max Sol: #{max_sol}"

    if start_sol > max_sol
      puts "✅ Up to date! No new photos."
      return
    end

    puts "🚀 Scraping Sols #{start_sol} to #{end_sol}..."

    # 4. Loop through the Sols
    (start_sol..end_sol).each do |sol|
      # Official API format: ?sol=1000&api_key=XYZ
      url = "#{BASE_URL}?sol=#{sol}&api_key=#{@api_key}"
      
      data = open_url(url)
      next if data.nil? # Skip if request failed

      response = JSON.parse(data)
      photos = response["photos"] # Official API uses "photos" array

      if photos.nil? || photos.empty?
        puts "🌑 Sol #{sol}: No photos found."
        next
      end

      puts "📸 Sol #{sol}: Found #{photos.count} photos. Saving..."
      
      photos.each do |photo_data|
        create_photo(photo_data)
      end
    end
  end

  private

  def create_photo(data)
    # Official API structure is flatter:
    # {
    #   "id": 102693,
    #   "sol": 1000,
    #   "camera": { "name": "FHAZ", "full_name": "Front Hazard..." },
    #   "img_src": "http://...",
    #   "earth_date": "2015-05-30"
    # }

    sol = data['sol']
    img_src = data['img_src']
    
    # Handle HTTP to HTTPS conversion if needed
    img_src.sub!('http:', 'https:') if img_src.start_with?('http:')

    camera_data = data['camera']
    camera = find_or_create_camera(camera_data)

    photo = Photo.find_or_initialize_by(sol: sol, camera: camera, img_src: img_src, rover: rover)
    
    if photo.new_record?
        photo.save 
        # Optional: Print a dot to show progress without spamming logs
        print "." 
    end
  end

  def find_or_create_camera(camera_data)
    name = camera_data['name']
    full_name = camera_data['full_name']

    camera = rover.cameras.find_by(name: name)

    if camera.nil?
      puts "\n⚠️ New Camera Found: #{name} (#{full_name}). Creating..."
      camera = rover.cameras.create(name: name, full_name: full_name)
    end

    camera
  end
end
