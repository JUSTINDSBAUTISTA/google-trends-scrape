require 'nokogiri'
require 'selenium-webdriver'
require 'csv'
require 'net/http'
require 'uri'
class GoogleTrendsScraper
  def initialize(email, password)
    @username = email
    @password = password
    @driver = nil
    @wait = nil
  end

  def login_to_google(driver, wait)
    driver.navigate.to("https://accounts.google.com/signin")
  
    # Enter email
    email_field = wait.until { driver.find_element(:id, 'identifierId') }
    email_field.send_keys(@username)
    driver.find_element(:id, 'identifierNext').click
  
    # Wait for the password field to appear
    wait.until { driver.find_element(:name, 'Passwd').displayed? }
  
    # Enter password
    password_field = driver.find_element(:name, 'Passwd')
    password_field.send_keys(@password)
    driver.find_element(:id, 'passwordNext').click
  
    # Wait for the "Continue" button is present and clickable
    continue_button = wait.until do
      element = driver.find_element(xpath: "//button[.//span[text()='Continue']]")
      element if element.displayed? # Ensure the element is displayed
    end
    
    # Click the "Continue" button
    continue_button.click

    # 2FA step
    puts "Please complete 2FA manually in the browser..."
    sleep(10) # Give time for 2FA
  end  

  # Fetch the Google Trends page after logging in with pagination
  def fetch_trends_pages(driver, wait, query, max_pages = 5)
    # Navigate to the Trends page
    driver.navigate.to("https://trends.google.com/trends/explore?date=today%203-m&geo=CA&q=#{query}&hl=en")
  
    # Wait for the page to load completely
    wait.until { driver.execute_script("return document.readyState") == "complete" }
  
    # Wait for the input element to be present and visible
    begin
      input_element = wait.until do
        element = driver.find_element(xpath: '//input[@type="search"]')
        element if element.displayed? && element.enabled?
      end
    rescue Selenium::WebDriver::Error::TimeoutError
      puts "Timeout while waiting for the input element. Check if the page is loaded properly and the element exists."
      driver.quit
      return []
    end
  
    # Scroll the input element into view
    driver.execute_script("arguments[0].scrollIntoView(true);", input_element)
    
    # Clear the input field and enter the query
    input_element.clear
    input_element.send_keys(query)
    
    # Simulate pressing Enter to submit the query
    input_element.send_keys(:enter)
    
    # Wait for the search results to load
    begin
      wait.until { driver.execute_script("return document.readyState") == "complete" }
      sleep(4)
    rescue Selenium::WebDriver::Error::TimeoutError
      puts "Timeout while waiting for the page to load after entering the query."
      driver.quit
      return []
    end
  
    all_data = []
    page_number = 1
  
    while page_number <= max_pages
      # Capture the page's HTML content
      html = driver.page_source
      page_data = parse_trends_page(html)
      all_data.concat(page_data)
  
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
        sleep(1) # Optional: Adjust sleep time if needed
      end
    end
  
    all_data
  end
  
  
  # Parse the fetched HTML and extract trends data
  def parse_trends_page(html)
    return [] unless html

    doc = Nokogiri::HTML.parse(html)

    begin
      containers = doc.css('div.fe-atoms-generic-content-container')
      if containers.size < 5
        puts "Error: Less than 5 'div.fe-atoms-generic-content-container' found in the page."
        return []
      end

      content_container = containers[4]
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
  def write_to_csv(data, filename = "#{@query.parameterize}.csv")
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
  
    login_to_google(@driver, @wait)
  
    queries.each do |query|
      filename ||= "#{query.parameterize}.csv"
      data = fetch_trends_pages(@driver, @wait, query, max_pages)
  
      if data.any?
        write_to_csv(data, filename)      # Save individual query data to separate CSV
        append_to_combined_csv(data)      # Append data to the combined CSV
      else
        puts "No data found to write to the CSV for query: #{query}."
      end
    end
  
    @driver.quit
  end  
  
end
