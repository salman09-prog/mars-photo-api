class CuriosityScraper
  require "open-uri"
  require 'json'

  # NOTE: This is the internal website API, not the official public API.
  # It does not strictly require an API key, but it BLOCKS requests without a User-Agent.
  BASE_URL = "https://mars.nasa.gov/api/v1/raw_image_items/"

  attr_reader :rover

  def initialize
    @rover = Rover.find_by(name: "Curiosity")
  end

  def scrape
    create_photos
  end

  # Helper to open URLs with a fake User-Agent to avoid 403 Forbidden
  def open_url(url)
    URI.open(url, "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36").read
  end

  def collect_links
    puts "🔍 checking for new photos..."
    
    # Use the helper method with User-Agent
    json_data = open_url(BASE_URL + "?order=sol%20desc,instrument_sort%20asc,sample_type_sort%20asc,%20date_taken%20desc&per_page=1&page=0&condition_1=msl:mission")
    response = JSON.parse(json_data)

    latest_sol_available = response["items"].first["sol"].to_i

    # Use 0 if no photos exist yet
    latest_sol_scraped = rover.photos.maximum(:sol).to_i || 0

    # Start from where we left off
    start_sol = latest_sol_scraped + 1

    # Stop after 50 sols (Safety limit to prevent timeout)
    end_sol = [start_sol + 50, latest_sol_available].min

    puts "📊 Status: DB has Sol #{latest_sol_scraped}. NASA has Sol #{latest_sol_available}."
    
    # If we are already caught up, don't do anything
    if start_sol > latest_sol_available
        puts "✅ Up to date! No new photos to scrape."
        return [] 
    end

    puts "🚀 Scraping from Sol #{start_sol} to #{end_sol}..."

    sols_to_scrape = (start_sol..end_sol)

    sols_to_scrape.map { |sol|
      "#{BASE_URL}?order=sol%20desc,instrument_sort%20asc,sample_type_sort%20asc,%20date_taken%20desc&per_page=200&page=0&condition_1=msl:mission&condition_2=#{sol}:sol:in"
    }
  end

  private

  def create_photos
    links = collect_links
    return if links.empty?

    links.each do |url|
      scrape_photo_page(url)
    end
  end

  def scrape_photo_page(url)
    begin
      # Use the helper method here too!
      json_data = open_url(url)
      response = JSON.parse(json_data)
      
      response['items'].each do |image|
        create_photo(image) if image['extended'] && image['extended']['sample_type'] == 'full'
      end
    rescue OpenURI::HTTPError => e
      puts "❌ HTTP error: #{e.message} for URL: #{url}. (Likely 403 Forbidden or 404)"
    rescue StandardError => e
      puts "❌ Error: #{e.message} for URL: #{url}."
    end
  end

  def create_photo(image)
    sol = image['sol']
    camera = camera_from_json(image)
    link = image['https_url']
    
    if camera.is_a?(String)
      puts "⚠️ WARNING: Camera not found. Name: #{camera}"
    else
      photo = Photo.find_or_initialize_by(sol: sol, camera: camera, img_src: link, rover: rover)
      # Assuming log_and_save_if_new is a method on your Photo model
      photo.save if photo.new_record? 
    end
  end

  def camera_from_json(image)
    camera_name = image['instrument']
    camera = rover.cameras.find_by(name: camera_name) || rover.cameras.find_by(full_name: camera_name)

    if camera.nil?
      # Log a warning
      puts "⚠️ Camera missing: #{camera_name}. Creating it now..."

      # Add the new camera to the database
      camera = rover.cameras.create(name: camera_name, full_name: camera_name)

      if camera.persisted?
        puts "✅ Created camera: #{camera_name}"
      else
        puts "❌ Failed to create camera: #{camera_name}"
      end
    end

    camera
  end
end
