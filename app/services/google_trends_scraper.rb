require 'nokogiri'
require 'selenium-webdriver'
require 'csv'
require 'net/http'
require 'uri'
require 'zip'

class GoogleTrendsScraper
  def initialize
    @driver = nil
    @wait = nil
    @first_reload_done = false # Initialize flag to track the first reload
    @zipfile_path = Rails.root.join('public', 'trends_data.zip') # Store the zip file path globally
  end

  def add_to_zip_file(query)
    # Exclude the combined CSV file
    combined_filename = "#{Date.today.strftime("%B_%d_%Y")}.csv"
    
    filename = "#{query[:tag].parameterize}.csv"
    csv_filepath = Rails.root.join('public', filename)

    if File.exist?(csv_filepath) && filename != combined_filename
      begin
        Zip::File.open(@zipfile_path, Zip::File::CREATE) do |zipfile|
          unless zipfile.find_entry(filename)
            zipfile.add(filename, csv_filepath)
            puts "[add_to_zip_file] Added file #{filename} to the ZIP file."
          end
        end
      rescue => e
        puts "[add_to_zip_file] Error adding to ZIP file: #{e.message}"
      end
    else
      puts "[add_to_zip_file] File #{filename} not found or it is the combined file. Skipping."
    end
  end

  def fetch_trends_pages(driver, wait, query, pick_date, max_pages = 5)
    # Use the tag in the Google Trends URL for search query
    tag = query[:tag]
    url = "https://trends.google.com/trends/explore?q=#{tag}&date=now%#{pick_date}&geo=US&hl=en-US"
    
    # Navigate to the URL
    driver.navigate.to(url)
  
    # Refresh the page after navigating to the URL
    driver.navigate.refresh
  
    # Wait for the page to reload completely after refresh
    wait.until { driver.execute_script("return document.readyState") == "complete" }
    sleep(rand(1.75..2.00))
  
 
    # Proceed with scraping once the page is successfully loaded
    all_data = []
    page_number = 1
    total_item_number = 1  # To keep track of global line numbers
  
    scroll_down_until_no_new_content(driver)
  
    while page_number <= max_pages
      html = driver.page_source
      page_data, next_button_found = parse_trends_page(html)
  
      if page_data.any?
        page_data.each do |item|
          item[:line_number] = total_item_number
          total_item_number += 1
          all_data << item
        end
        puts "[fetch_trends_page] Scraped data from page #{page_number}."
      else
        puts "[fetch_trends_page] No data found on page #{page_number}. Ending scraping."
        break
      end
  
      # Handle pagination based on the presence of the Next button
      if next_button_found
        begin
          next_buttons = driver.find_elements(css: 'button[aria-label="Next"]')
  
          if next_buttons.any?
            next_button = next_buttons.last
            if next_button.displayed? && next_button.enabled?
              driver.execute_script("arguments[0].scrollIntoView(true);", next_button)
              wait.until { next_button.displayed? && next_button.enabled? }
              next_button.click
              wait.until { driver.execute_script("return document.readyState") == "complete" }
              page_number += 1
            else
              puts "[fetch_trends_page] Next button is present but not clickable. Ending pagination."
              break
            end
          else
            puts "[fetch_trends_page] No more 'Next' buttons found, ending pagination."
            break
          end
        rescue Selenium::WebDriver::Error::NoSuchElementError
          puts "[fetch_trends_page] No 'Next' button found, ending pagination."
          break
        rescue Selenium::WebDriver::Error::ElementClickInterceptedError
          puts "[fetch_trends_page] Element click intercepted, trying to handle overlay or obstruction."
        end
      else
        puts "[fetch_trends_page] No 'Next' button found, ending pagination."
        break
      end
    end
  
    all_data
  end
  
  # Scroll down the page until no new content appears
  def scroll_down_until_no_new_content(driver)
    previous_height = driver.execute_script("return document.body.scrollHeight")
    max_scroll_attempts = 2  # Limit scroll attempts to prevent infinite loop
    scroll_attempts = 0

    while scroll_attempts < max_scroll_attempts
      # Scroll to the bottom of the page
      driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
      sleep(1) # Give time for lazy-loaded content to load

      new_height = driver.execute_script("return document.body.scrollHeight")
      if new_height == previous_height
        break  # No more new content to load
      end

      previous_height = new_height
      scroll_attempts += 1
    end
  end

  def parse_trends_page(html)
    return [], false unless html
  
    doc = Nokogiri::HTML.parse(html)
  
    begin
      # Target the 'trends-widget' with 'widget-name="RELATED_QUERIES"'
      trends_widgets = doc.css('trends-widget[widget-name="RELATED_QUERIES"]')
  
      if trends_widgets.empty?
        puts "[parse_trends_page] No 'trends-widget' with 'RELATED_QUERIES' found. Skipping this query."
        return [], false
      end
  
      related_queries_container = trends_widgets.css('div.fe-related-queries.fe-atoms-generic-container')
  
  
      if related_queries_container.empty?
        puts "[parse_trends_page] No 'fe-related-queries' container found within the 'RELATED_QUERIES' widget."
        return [], false
      else
        puts "[parse_trends_page] 'RELATED_QUERIES' widget and 'fe-related-queries' container found."
      end
  
      # Extract items within the related queries container
      items = related_queries_container.css('div.item')
  
      if items.empty?
        puts "[parse_trends_page] No items found in the related queries container."
        return [], false
      end
  
      # Extract data from the items
      data = items.map do |item|
        link_element = item.at_css('div.progress-label-wrapper a.progress-label')
        link_href = link_element ? link_element['href'] : ''
  
        seed = item.at_css('div.label-text span')&.text&.strip
        rising_value = item.at_css('div.rising-value')&.text&.strip
  
        {
          link: link_href,
          seed: seed,
          rising_value: rising_value
        }
      end
  
      # Check if there is a "Next" button inside the trends_widgets
      next_button = trends_widgets.at_css('button[aria-label="Next"]')
  
      next_button_found = next_button && next_button['disabled'].nil?
      return data, next_button_found
  
    rescue => e
      puts "[parse_trends_page] Error parsing trends page: #{e.message}"
      return [], false
    end
  end

  # Method to append data to a combined CSV file with idType and tagType
  def append_to_combined_csv(data, query)
    if data.empty?
      puts "[append_to_combined_csv] No data available to append to the combined CSV file."
      return
    end

    # Get the current date formatted as 'Month_Date_Year'
    current_date_str = Date.today.strftime("%B_%d_%Y")

    # Dynamically rename the combined CSV file based on the current date
    combined_filename = "#{current_date_str}.csv"
    filepath = Rails.root.join('public', combined_filename)
    current_date = Date.today.strftime('%Y-%m-%d')

    begin
      CSV.open(filepath, "a+", headers: true) do |csv|
        if csv.count.zero?
          # Add headers only if the file is empty (newly created)
          csv << ["Query", "Line Number", "Seed", "Link", "Rising Value", "idType", "tagType", "Date"]
        end
        data.each do |entry|
          csv << [query[:tag].upcase, entry[:line_number], entry[:seed].capitalize, "https://trends.google.ca#{entry[:link]}", entry[:rising_value], query[:idType].to_i, query[:tagType], current_date]
        end
      end
      puts "[append_to_combined_csv] CSV file '#{combined_filename}' updated successfully."
    rescue => e
      puts "[append_to_combined_csv] Error writing to combined CSV file '#{combined_filename}': #{e.message}"
    end
  end

  # Method to write data to a CSV file
  def write_to_csv(data, filename, query)
    if data.empty?
      puts "[write_to_csv] No data available to write to the CSV file."
      return
    end

    filepath = Rails.root.join('public', filename)
    current_date = Date.today.strftime('%Y-%m-%d')

    begin
      CSV.open(filepath, "wb", headers: true) do |csv|
        csv << ["Query", "Line Number", "Seed", "Link", "Rising Value", "idType", "tagType", "Date"]
        data.each do |entry|
          csv << [query[:tag], entry[:line_number], entry[:seed].capitalize, "https://trends.google.ca#{entry[:link]}", entry[:rising_value], query[:idType].to_i, query[:tagType], current_date]
        end
      end
      puts "[write_to_csv] CSV file '#{filename}' written successfully."

      # Immediately add the written CSV to the zip file
      add_to_zip_file(query)

    rescue => e
      puts "[write_to_csv] Error writing CSV file '#{filename}': #{e.message}"
    end
  end

  def fetch_and_export_trends(queries, pick_date = '201-d', max_pages = 5)
    options = Selenium::WebDriver::Chrome::Options.new
    user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36'
    options.add_argument("user-agent=#{user_agent}")
  
    successful_scrapes = 0
    unsuccessful_scrapes = 0
  
    # Iterate over the queries in batches
    queries.each_slice(rand(6..9)).with_index do |query_batch, index|
      # Open a new browser instance for each batch of queries
      @driver = Selenium::WebDriver.for :chrome, options: options
      @wait = Selenium::WebDriver::Wait.new(timeout: 20)
  
      query_batch.each do |query|
        filename = "#{query[:tag].parameterize}.csv"
        data = fetch_trends_pages(@driver, @wait, query, pick_date, max_pages)
  
        if data.any?
          successful_scrapes += 1
          write_to_csv(data, filename, query)
          append_to_combined_csv(data, query)
          puts "[fetch_and_export_trends] Data written to CSV for query: #{query[:tag]}."
        else
          unsuccessful_scrapes += 1
          puts "[fetch_and_export_trends] No data found to write to the CSV for query: #{query[:tag]}."
        end
      end
  
      # Close the current browser
      @driver.quit
      puts "[fetch_and_export_trends] Browser closed after batch #{index + 1}."
  
      # Change VPN location before opening a new browser instance
      change_vpn_location
  
      puts "[fetch_and_export_trends] Opening new browser for next batch."
    end
  
    puts "[fetch_and_export_trends] Total successful scrapes: #{successful_scrapes}"
    puts "[fetch_and_export_trends] Total unsuccessful scrapes: #{unsuccessful_scrapes}"
  end
  
  # Method to change VPN location by running the AppleScript
  def change_vpn_location
    begin
      puts "[change_vpn_location] Changing VPN location..."
      # Assuming your AppleScript is saved as change_vpn_location.scpt in the project root
      system("osascript #{Rails.root.join('location_handler.scpt')}")

      sleep(2)

      puts "[change_vpn_location] VPN location changed successfully."


      # Fetch and print the current public IP address
      current_ip = fetch_current_ip
      puts "[change_vpn_location] Current IP address: #{current_ip}"

    rescue => e
      puts "[change_vpn_location] Error changing VPN location: #{e.message}"
    end
  end

    # Helper method to fetch the current public IP address
    def fetch_current_ip
      begin
        uri = URI.parse("https://api.ipify.org")
        response = Net::HTTP.get_response(uri)
        if response.is_a?(Net::HTTPSuccess)
          response.body
        else
          "Unable to fetch IP address"
        end
      rescue => e
        "Error fetching IP address: #{e.message}"
      end
    end

end
