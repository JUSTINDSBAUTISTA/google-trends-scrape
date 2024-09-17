require 'nokogiri'
require 'selenium-webdriver'
require 'csv'
require 'net/http'
require 'uri'

class GoogleTrendsScraper
  def initialize(query, email, password)
    @query = query
    @email = email
    @password = password
  end

  # Fetch the Google Trends page after logging in with pagination
  def fetch_trends_pages(max_pages = 5)
    begin
      options = Selenium::WebDriver::Chrome::Options.new
      user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'
      options.add_argument("user-agent=#{user_agent}")
  
      driver = Selenium::WebDriver.for :chrome, options: options
      wait = Selenium::WebDriver::Wait.new(timeout: 60) # Increased wait time for 2FA
  
      # Navigate to Google login page
      driver.navigate.to("https://accounts.google.com/signin")
  
      # Enter email
      email_field = wait.until { driver.find_element(:id, 'identifierId') }
      email_field.send_keys(@email)
      driver.find_element(:id, 'identifierNext').click
  
      # Wait for the password field to appear
      wait.until { driver.find_element(:name, 'Passwd').displayed? }
  
      # Enter password
      password_field = driver.find_element(:name, 'Passwd')
      password_field.send_keys(@password)
      driver.find_element(:id, 'passwordNext').click
  
      # 2FA step
      puts "Please complete 2FA manually in the browser..."
      sleep(20) # Give time for 2FA
  
      # Navigate to the Trends page
      url = "https://trends.google.ca/trends/explore?q=#{@query}&date=now%207-d&geo=CA&hl=en-GB"
      driver.navigate.to(url)
  
      all_data = []
      page_number = 1
  
      while page_number <= max_pages
        # Capture the page's HTML content
        sleep(5)
        html = driver.page_source
      
        # Parse and collect data from the current page
        page_data = parse_trends_page(html)
        all_data.concat(page_data)
      
        begin
          # Wait until the "Next" button is visible and enabled
          next_buttons = driver.find_elements(css: 'button[aria-label="Next"]')
      
          if next_buttons.any?
            next_button = next_buttons.last
      
            # Check if the "Next" button is enabled and clickable
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
          sleep(2) # Retry after a short delay
        end
      end
      
      driver.quit
      all_data
      
    rescue Selenium::WebDriver::Error::TimeoutError => e
      puts "Error: Operation timed out. Make sure you've completed the 2FA: #{e.message}"
      driver.quit if driver
      nil
    rescue => e
      puts "An error occurred: #{e.message}"
      driver.quit if driver
      nil
    end
  end
  
  
  # Parse the fetched HTML and extract trends data
  def parse_trends_page(html)
    return [] unless html
  
    doc = Nokogiri::HTML.parse(html)
  
    begin
      containers = doc.css('div.fe-atoms-generic-content-container')
      puts "Number of containers found: #{containers.size}"
      if containers.size < 5
        puts "Error: Less than 5 'div.fe-atoms-generic-content-container' found in the page."
        return []
      end
  
      content_container = containers[4]
  
      puts "Selected 3rd container:"
      puts content_container.to_html
  
      items = content_container.css('div.item')
  
      if items.nil? || items.empty?
        puts "No items found in 'div.item'."
        return []
      else
        items.each_with_index do |item, index|
          puts "Item #{index + 1}:"
          puts item.to_html
        end
      end
  
      data = items.map do |item|
        link_element = item.at_css('div.progress-label-wrapper a.progress-label')
        link_href = link_element ? link_element['href'] : ''
  
        label_text = item.at_css('div.label-text span')&.text&.strip
        rising_value = item.at_css('div.rising-value')&.text&.strip
        line_number = item.at_css('div.label-line-number')&.text&.strip
  
        {
          link: link_href,
          label_text: label_text,
          rising_value: rising_value,
          line_number: line_number
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

  # Method to write data to a CSV file
  def write_to_csv(data, filename = "trends_data.csv")
    if data.empty?
      puts "No data available to write to the CSV file."
      return
    end
  
    filepath = Rails.root.join('public', filename) # Save file in the public directory
  
    begin
      CSV.open(filepath, "wb") do |csv|
        csv << ["Link", "Label Text", "Rising Value", "Line Number"]
        data.each do |entry|
          csv << ["https://trends.google.ca#{entry[:link]}", entry[:label_text], entry[:rising_value], entry[:line_number]]
        end
      end
      puts "CSV file '#{filename}' written successfully."
    rescue => e
      puts "Error writing CSV file '#{filename}': #{e.message}"
    end
  end
  

  # Main method to fetch and export trends
  def fetch_and_export_trends(filename = "trends_data.csv", max_pages = 5)
    data = fetch_trends_pages(max_pages)

    if data.any?
      write_to_csv(data, filename)
    else
      puts "No data found to write to the CSV."
    end
  end
end
