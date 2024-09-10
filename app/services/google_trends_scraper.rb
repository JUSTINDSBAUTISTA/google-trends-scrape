require 'nokogiri'
require 'selenium-webdriver'
require 'csv'

class GoogleTrendsScraper
  def initialize(query)
    @query = query
  end

  def fetch_trends_page
    begin
      options = Selenium::WebDriver::Chrome::Options.new
      user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
      options.add_argument("user-agent=#{user_agent}")

      driver = Selenium::WebDriver.for :chrome, options: options
      url = "https://trends.google.ca/trends/explore?q=#{@query}&date=now%201-d&geo=CA&hl=en-GB"
      driver.navigate.to(url)

      # Wait for the page to load
      sleep(15)  # Increase this wait time to at least 15 seconds to avoid rapid requests

      html = driver.page_source
      # driver.quit
      html
    rescue => e
      puts "Error fetching trends page: #{e.message}"
      nil
    end
  end



  def parse_trends_page(html)
    return [] unless html

    doc = Nokogiri::HTML.parse(html)

    begin
      # Output the HTML for debugging
      puts doc.to_html

      # Find the main container
      container = doc.at_css('div.fe-related-queries')
      if container.nil?
        puts "Error: 'div.fe-related-queries' not found in the page."
        return []
      end

      # Find the content container within the main container
      content_container = container.at_css('div.fe-atoms-generic-content-container')
      if content_container.nil?
        puts "Error: 'div.fe-atoms-generic-content-container' not found."
        return []
      end

      # Extract items
      items = content_container.css('div.item').first(20) # Limit to 20 items

      data = items.map do |item|
        link_element = item.at_css('div.progress-label-wrapper a.progress-label')
        link_href = link_element ? link_element['href'] : ''

        label_text = item.at_css('div.label-text span')&.text&.strip
        rising_value = item.at_css('div.rising-value')&.text&.strip

        {
          link: link_href,
          label_text: label_text,
          rising_value: rising_value
        }
      end

      puts "Parsed Data:"
      puts data.inspect
      data
    rescue => e
      puts "Error parsing trends page: #{e.message}"
      []
    end
  end

  def write_to_csv(data)
    begin
      CSV.open("trends_data.csv", "wb") do |csv|
        # Adding a header row
        csv << ["Link", "Label Text", "Rising Value"]
        data.each do |entry|
          csv << [entry[:link], entry[:label_text], entry[:rising_value]]
        end
      end
      puts "CSV file written successfully."
    rescue => e
      puts "Error writing CSV file: #{e.message}"
    end
  end

  def fetch_and_export_trends
    html = fetch_trends_page
    data = parse_trends_page(html)
    write_to_csv(data)
  end
end

# # Usage
# scraper = GoogleTrendsScraper.new('technology')
# scraper.fetch_and_export_trends
