# config/initializers/auto_scrape.rb

# We wrap this in a thread so it doesn't block the server from starting
Thread.new do
  # Wait 10 seconds to let the server fully boot up
  sleep 10
  
  puts "🚀 Auto-Scraper: Starting background scrape of 50 Sols..."
  
  begin
    # Call your existing scraper class here
    CuriosityScraper.new.scrape 
    puts "✅ Auto-Scraper: Finished successfully!"
  rescue => e
    puts "❌ Auto-Scraper Failed: #{e.message}"
    puts e.backtrace.first(5) # Optional: prints line numbers if it fails
  end
end
