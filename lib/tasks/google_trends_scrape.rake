require 'nokogiri'
require 'httparty'
require 'csv'

namespace :scrape do
  desc "Scrape Google Trends for specific data"
  task google_trends: :environment do
    # Step 1: Fetch Google Trends Page (HTML)
    url = "https://trends.google.com/trends/explore?q=star%20wars&date=now%201-d&geo=CA&hl=en-GB"

    # Use HTTParty to fetch the page content
    response = HTTParty.get(url)

    # Step 2: Parse HTML
    doc = Nokogiri::HTML(response.body)

    # Step 3: Extract Specific Data
    data = []

    doc.css('.item').each do |item|
      # Extract the href from <a> tag inside .progress-label
      link = item.css('a.progress-label').attr('href').value

      # Extract the text inside the <span> under .label-text
      text = item.css('.label-text span').text

      # Extract the rising value text inside .rising-value
      rising_value = item.css('.rising-value').text

      # Store the extracted data into an array
      data << [text, link, rising_value]
    end

    # Step 4: Write Data to CSV
    CSV.open("google_trends_data.csv", "w") do |csv|
      csv << ["Query", "Link", "Rising Value"] # Header row
      data.each do |row|
        csv << row
      end
    end

    puts "Data successfully scraped and saved to google_trends_data.csv"
  end
end
