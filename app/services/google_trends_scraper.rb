require 'nokogiri'
require 'selenium-webdriver'
require 'csv'
require 'net/http'
require 'uri'
require 'zip'

class GoogleTrendsScraper
  def initialize
    @zipfile_path = Rails.root.join('public', 'trends_data.zip') # Store the zip file path globally
  end

  # Method to add a query CSV file to a ZIP archive
  def add_to_zip_file(query)
    combined_filename = "#{Date.today.strftime('%B_%d_%Y')}.csv"
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

  # Method to fetch trends from Google Trends and paginate through pages
  def fetch_trends_pages(driver, wait, query, pick_date, max_pages = 5)
    tag = query[:tag]
    url = "https://trends.google.com/trends/explore?q=#{tag}&date=now%#{pick_date}&geo=US&hl=en-US"
    
    driver.navigate.to(url)
    driver.navigate.refresh
    wait.until { driver.execute_script("return document.readyState") == "complete" }
    sleep(rand(1.75..2.00))

    all_data = []
    page_number = 1
    total_item_number = 1
  
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

      break unless next_button_found

      begin
        next_buttons = driver.find_elements(css: 'button[aria-label="Next"]')
        next_button = next_buttons.last
        if next_button.displayed? && next_button.enabled?
          driver.execute_script("arguments[0].scrollIntoView(true);", next_button)
          next_button.click
          wait.until { driver.execute_script("return document.readyState") == "complete" }
          page_number += 1
        end
      rescue Selenium::WebDriver::Error::NoSuchElementError, Selenium::WebDriver::Error::ElementClickInterceptedError
        puts "[fetch_trends_page] Error with Next button. Ending pagination."
        break
      end
    end

    all_data
  end

  # Scroll method
  def scroll_down_until_no_new_content(driver)
    previous_height = driver.execute_script("return document.body.scrollHeight")
    max_scroll_attempts = 2
    scroll_attempts = 0

    while scroll_attempts < max_scroll_attempts
      driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
      sleep(1) 
      new_height = driver.execute_script("return document.body.scrollHeight")
      break if new_height == previous_height
      previous_height = new_height
      scroll_attempts += 1
    end
  end


  def parse_trends_page(html)
    return [], false unless html
  
    doc = Nokogiri::HTML.parse(html)
    trends_widgets = doc.css('trends-widget[widget-name="RELATED_QUERIES"]')

    return [], false if trends_widgets.empty?

    related_queries_container = trends_widgets.css('div.fe-related-queries.fe-atoms-generic-container')
    return [], false if related_queries_container.empty?

    items = related_queries_container.css('div.item')
    return [], false if items.empty?

    data = items.map do |item|
      link_element = item.at_css('div.progress-label-wrapper a.progress-label')
      link_href = link_element ? link_element['href'] : ''
      seed = item.at_css('div.label-text span')&.text&.strip
      rising_value = item.at_css('div.rising-value')&.text&.strip
  
      { link: link_href, seed: seed, rising_value: rising_value }
    end
  
    next_button = trends_widgets.at_css('button[aria-label="Next"]')
    next_button_found = next_button && next_button['disabled'].nil?
  
    [data, next_button_found]
  end

  def append_to_combined_csv(data, query)
    return if data.empty?

    current_date_str = Date.today.strftime('%B_%d_%Y')
    combined_filename = "#{current_date_str}.csv"
    filepath = Rails.root.join('public', combined_filename)
    current_date = Date.today.strftime('%Y-%m-%d')

    begin
      CSV.open(filepath, "a+", headers: true) do |csv|
        csv << ["Query", "Line Number", "Seed", "Link", "Rising Value", "idType", "tagType", "Date"] if csv.count.zero?
        data.each do |entry|
          csv << [query[:tag].upcase, entry[:line_number], entry[:seed].capitalize, "https://trends.google.ca#{entry[:link]}", entry[:rising_value], query[:idType].to_i, query[:tagType], current_date]
        end
      end
      puts "[append_to_combined_csv] CSV file '#{combined_filename}' updated successfully."
    rescue => e
      puts "[append_to_combined_csv] Error writing to combined CSV file '#{combined_filename}': #{e.message}"
    end
  end

  def write_to_csv(data, filename, query)
    return if data.empty?

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
      add_to_zip_file(query)
    rescue => e
      puts "[write_to_csv] Error writing CSV file '#{filename}': #{e.message}"
    end
  end

  def change_vpn_location
    begin
      puts "[change_vpn_location] Changing VPN location..."
      system("osascript #{Rails.root.join('location_handler.scpt')}")
      sleep(2)
      current_ip = fetch_current_ip
      puts "[change_vpn_location] Current IP address: #{current_ip}"
    rescue => e
      puts "[change_vpn_location] Error changing VPN location: #{e.message}"
    end
  end

  def fetch_current_ip
    uri = URI.parse("https://api.ipify.org")
    response = Net::HTTP.get_response(uri)
    response.is_a?(Net::HTTPSuccess) ? response.body : "Unable to fetch IP address"
  rescue => e
    "Error fetching IP address: #{e.message}"
  end
end
