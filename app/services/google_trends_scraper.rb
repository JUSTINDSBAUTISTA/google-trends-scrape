require 'nokogiri'
require 'selenium-webdriver'
require 'csv'
require 'net/http'
require 'uri'

class GoogleTrendsScraper
  def initialize
    @driver = nil
    @wait = nil
    @first_reload_done = false # Initialize flag to track the first reload
  end

  # Fetch the Google Trends page with pagination logic
  def fetch_trends_pages(driver, wait, query, max_pages = 5)
    driver.navigate.to("https://trends.google.com/trends/explore?q=#{query}&date=now%201-d&geo=CA&hl=en-US")

    # Wait for the page to load completely
    wait.until { driver.execute_script("return document.readyState") == "complete" }

    all_data = []
    page_number = 1
    total_item_number = 1  # To keep track of global line numbers

    while page_number <= max_pages
      # Ensure the page is scrolled to load all content
      scroll_down_until_no_new_content(driver)

      # Scrape the data from the current page
      html = driver.page_source
      sleep(rand(2..3))
      page_data = parse_trends_page(html)

      # Ensure that data from the current page is unique and non-empty
      if page_data.any?
        page_data.each do |item|
          # Add a global line number to the data
          item[:line_number] = total_item_number
          total_item_number += 1
          all_data << item
        end
        puts "Scraped data from page #{page_number}."
      else
        puts "No data found on page #{page_number}. Ending scraping."
        break
      end

      # Try to find and click the "Next" button for pagination
      begin
        next_buttons = driver.find_elements(css: 'button[aria-label="Next"]')

        if next_buttons.any?
          next_button = next_buttons.last

          # Ensure the button is displayed and clickable
          if next_button.displayed? && next_button.enabled?
            driver.execute_script("arguments[0].scrollIntoView(true);", next_button)
            wait.until { next_button.displayed? && next_button.enabled? }
            next_button.click
            wait.until { driver.execute_script("return document.readyState") == "complete" }
            page_number += 1
          else
            puts "Next button is present but not clickable. Ending pagination."
            break
          end
        else
          puts "No more 'Next' buttons found, ending pagination."
          break
        end
      rescue Selenium::WebDriver::Error::NoSuchElementError
        puts "No 'Next' button found, ending pagination."
        break
      rescue Selenium::WebDriver::Error::ElementClickInterceptedError
        puts "Element click intercepted, trying to handle overlay or obstruction."
        sleep(1)
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
      sleep(2) # Give time for lazy-loaded content to load

      new_height = driver.execute_script("return document.body.scrollHeight")
      if new_height == previous_height
        break  # No more new content to load
      end

      previous_height = new_height
      scroll_attempts += 1
    end
  end

  # Parse the fetched HTML and extract trends data
  def parse_trends_page(html)
    return [] unless html

    doc = Nokogiri::HTML.parse(html)

    begin
      containers = doc.css('div.fe-atoms-generic-content-container')
      puts "Found #{containers.size} 'div.fe-atoms-generic-content-container' containers"

      if containers.size < 5
        puts "Less than 5 'div.fe-atoms-generic-content-container' found. Skipping this query."
        return []
      end

      content_container = containers[4] # Target the 5th container
      puts "5th container HTML: #{content_container.to_html}" # Debugging: Print HTML

      items = content_container.css('div.item')

      if items.nil? || items.empty?
        puts "No items found in the 5th 'div.item'."
        return []
      end

      # Extract data from the items
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

      data
    rescue => e
      puts "Error parsing trends page: #{e.message}"
      []
    end
  end

  # Method to append data to a combined CSV file
  def append_to_combined_csv(data)
    if data.empty?
      puts "No data available to append to the combined CSV file."
      return
    end

    combined_filename = 'all_trends_data.csv' # Name of the combined CSV file
    filepath = Rails.root.join('public', combined_filename) # Save file in the public directory

    begin
      CSV.open(filepath, "a+") do |csv|
        if csv.count.zero?
          # Add headers only if the file is empty (newly created)
          csv << ["Line Number", "Label Text", "Link", "Rising Value"]
        end
        data.each do |entry|
          csv << [entry[:line_number], entry[:label_text].capitalize, "https://trends.google.ca#{entry[:link]}", entry[:rising_value]]
        end
      end
      puts "CSV file 'all_trends_data.csv' updated successfully."
    rescue => e
      puts "Error writing to combined CSV file 'all_trends_data.csv': #{e.message}"
    end
  end

  # Method to write data to a CSV file
  def write_to_csv(data, filename)
    if data.empty?
      puts "No data available to write to the CSV file."
      return
    end

    filepath = Rails.root.join('public', filename) # Save file in the public directory

    begin
      CSV.open(filepath, "wb") do |csv|
        csv << ["Line Number", "Label Text", "Link", "Rising Value"]
        data.each do |entry|
          csv << [entry[:line_number], entry[:label_text].capitalize, "https://trends.google.ca#{entry[:link]}", entry[:rising_value]]
        end
      end
      puts "CSV file '#{filename}' written successfully."
    rescue => e
      puts "Error writing CSV file '#{filename}': #{e.message}"
    end
  end

  # Main method to fetch and export trends
  def fetch_and_export_trends(queries, max_pages = 5)
    options = Selenium::WebDriver::Chrome::Options.new
    user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36'
    options.add_argument("user-agent=#{user_agent}")
    
    @driver = Selenium::WebDriver.for :chrome, options: options
    @wait = Selenium::WebDriver::Wait.new(timeout: 20)
  
    # Loop through the queries in randomized batches of 3 to 5
    queries.each_slice(rand(3..5)).with_index do |query_batch, index|
      query_batch.each do |query|
        filename = "#{query.parameterize}.csv"
        data = fetch_trends_pages(@driver, @wait, query, max_pages)
  
        if data.any?
          write_to_csv(data, filename)      # Save individual query data to separate CSV
          append_to_combined_csv(data)      # Append data to the combined CSV
        else
          puts "No data found to write to the CSV for query: #{query}."
        end
      end
  
      # After processing the randomized batch of queries, open a new tab and close the old one
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
  end
  
end
