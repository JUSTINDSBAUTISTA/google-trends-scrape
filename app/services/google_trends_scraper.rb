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
  end

  def create_zip_from_csv_files(queries)
    zipfile_name = Rails.root.join('public', 'trends_data.zip')

    begin
      Zip::File.open(zipfile_name, Zip::File::CREATE) do |zipfile|
        queries.each do |query|
          filename = "#{query.parameterize}.csv"
          csv_filepath = Rails.root.join('public', filename)

          # Only include the CSV file if it exists
          if File.exist?(csv_filepath)
            zipfile.add(filename, csv_filepath)
            puts "\n"
            puts "File that is found for query: #{query} is added to the ZIP file."
            puts "_" * 60
          else
            puts "\n"
            puts "File not found for query: #{query}"
          end 
        end
      end
      puts "\n"
      puts "_" * 60
      puts "\n"
      puts "ZIP file 'trends_data.zip' created successfully."
    rescue => e
      puts "Error creating ZIP file: #{e.message}"
    end
  end

  # Fetch the Google Trends page with pagination logic
  def fetch_trends_pages(driver, wait, query, pick_date, max_pages = 5)
    # Use the pick_date in the Google Trends URL
    driver.navigate.to("https://trends.google.com/trends/explore?q=#{query}&date=now%#{pick_date}&geo=CA&hl=en-US")
  
    # Wait for the page to load completely
    wait.until { driver.execute_script("return document.readyState") == "complete" }
    sleep(rand(2.0..3.0))
  
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
      sleep(rand(2.0..3.0)) # Give time for lazy-loaded content to load

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
  
  
  # Method to append data to a combined CSV file
  def append_to_combined_csv(data, query)
    if data.empty?
      puts "[append_to_combined_csv] No data available to append to the combined CSV file."
      return
    end

    combined_filename = 'all_trends_data.csv' # Name of the combined CSV file
    filepath = Rails.root.join('public', combined_filename) # Save file in the public directory
    current_date = Date.today.strftime('%Y-%m-%d') # Get current date in YYYY-MM-DD format

    begin
      CSV.open(filepath, "a+") do |csv|
        if csv.count.zero?
          # Add headers only if the file is empty (newly created)
          csv << ["Query", "Line Number", "Seed", "Link", "Rising Value", "Date"] # Add "Date" column
        end
        data.each do |entry|
          csv << [query.upcase, entry[:line_number], entry[:seed].capitalize, "https://trends.google.ca#{entry[:link]}", entry[:rising_value], current_date]
        end
      end
      puts "[append_to_combined_csv] CSV file 'all_trends_data.csv' updated successfully."
    rescue => e
      puts "[append_to_combined_csv] Error writing to combined CSV file 'all_trends_data.csv': #{e.message}"
    end
  end

  # Method to write data to a CSV file
  def write_to_csv(data, filename, query)
    if data.empty?
      puts "[write_to_csv] No data available to write to the CSV file."
      return
    end

    filepath = Rails.root.join('public', filename) # Save file in the public directory
    current_date = Date.today.strftime('%Y-%m-%d') # Get current date in YYYY-MM-DD format

    begin
      CSV.open(filepath, "wb") do |csv|
        csv << ["Query", "Line Number", "Seed", "Link", "Rising Value", "Date"] # Add "Date" column
        data.each do |entry|
          csv << [query, entry[:line_number], entry[:seed].capitalize, "https://trends.google.ca#{entry[:link]}", entry[:rising_value], current_date]
        end
      end
      puts "[write_to_csv] CSV file '#{filename}' written successfully."
    rescue => e
      puts "[write_to_csv] Error writing CSV file '#{filename}': #{e.message}"
    end
  end


  # Main method to fetch and export trends
  
  def fetch_and_export_trends(queries, pick_date, max_pages = 5)
    options = Selenium::WebDriver::Chrome::Options.new
    user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36'
    options.add_argument("user-agent=#{user_agent}")

    @driver = Selenium::WebDriver.for :chrome, options: options
    @wait = Selenium::WebDriver::Wait.new(timeout: 20)

    successful_scrapes = 0
    unsuccessful_scrapes = 0

    queries.each_slice(rand(3..5)).with_index do |query_batch, index|
      query_batch.each do |query|
        filename = "#{query.parameterize}.csv"
        data = fetch_trends_pages(@driver, @wait, query, pick_date, max_pages)

        if data.any?
          successful_scrapes += 1
          write_to_csv(data, filename, query)
          append_to_combined_csv(data, query)
          puts "[fetch_and_export_trends] Data written to CSV for query: #{query}."
        else
          unsuccessful_scrapes += 1
          puts "[fetch_and_export_trends] No data found to write to the CSV for query: #{query}."
        end
      end

      if (index + 1) < (queries.size / query_batch.size.to_f).ceil
        @driver.execute_script("window.open('about:blank', '_blank');")
        new_tab_handle = @driver.window_handles.last
        old_tab_handle = @driver.window_handles.first

        @driver.switch_to.window(new_tab_handle)

        if old_tab_handle != new_tab_handle
          @driver.switch_to.window(old_tab_handle)
          @driver.close
        end

        @driver.switch_to.window(new_tab_handle)
      end
    end

    @driver.quit
    create_zip_from_csv_files(queries)
    puts "[fetch_and_export_trends] Total successful scrapes: #{successful_scrapes}"
    puts "[fetch_and_export_trends] Total unsuccessful scrapes: #{unsuccessful_scrapes}"
  end
end
