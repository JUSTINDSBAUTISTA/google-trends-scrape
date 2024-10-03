require 'selenium-webdriver'
require 'redis'

class GoogleTrendsScrapingJob < ApplicationJob
  queue_as :default

  REDIS_SUCCESS_KEY = 'total_successful_scrapes'
  REDIS_UNSUCCESS_KEY = 'total_unsuccessful_scrapes'
  REDIS_WORKERS_KEY = 'google_trends_workers_done'

  def perform(query_batch, pick_date, max_pages, total_workers = 7)
    redis = Redis.new
    begin
      # Log the start time
      start_time = Time.now
      puts "[GoogleTrendsScrapingJob] Worker started at: #{start_time}"

      # Initialize counters for tracking scrapes
      successful_scrapes = 0
      unsuccessful_scrapes = 0

      # Setting up headless mode for Selenium Chrome
      options = Selenium::WebDriver::Chrome::Options.new
      user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36'
      options.add_argument("user-agent=#{user_agent}")
      options.add_argument('--headless')  # Running Chrome in headless mode
      options.add_argument('--disable-gpu')
      options.add_argument('--no-sandbox')
      options.add_argument('--disable-dev-shm-usage')

      # Open a new browser instance in headless mode for each batch
      driver = Selenium::WebDriver.for :chrome, options: options
      wait = Selenium::WebDriver::Wait.new(timeout: 20)

      query_batch.each do |query|
        scraper = GoogleTrendsScraper.new
        filename = "#{query[:tag].parameterize}.csv"
        data = scraper.fetch_trends_pages(driver, wait, query, pick_date, max_pages)

        if data.any?
          scraper.write_to_csv(data, filename, query)
          scraper.append_to_combined_csv(data, query)
          successful_scrapes += 1  # Increment successful scrape counter
          puts "[GoogleTrendsScrapingJob] Data written to CSV for query: #{query[:tag]}."
        else
          unsuccessful_scrapes += 1  # Increment unsuccessful scrape counter
          puts "[GoogleTrendsScrapingJob] No data found to write to the CSV for query: #{query[:tag]}."
        end
      end

      # Close the browser
      driver.quit
      puts "[GoogleTrendsScrapingJob] Browser closed for this batch."

      # Increment the Redis counter for completed workers
      workers_done = redis.incr(REDIS_WORKERS_KEY)
      puts "[GoogleTrendsScrapingJob] Workers completed: #{workers_done}/#{total_workers}"

      # Log the start and end times, calculate the duration
      end_time = Time.now
      duration = end_time - start_time
      puts "[GoogleTrendsScrapingJob] Worker finished at: #{end_time}, Duration: #{duration} seconds"

      # Log the number of successful and unsuccessful scrapes
      puts "[GoogleTrendsScrapingJob] Scraping Summary for this Worker:"
      puts "[GoogleTrendsScrapingJob] Successful scrapes: #{successful_scrapes}"
      puts "[GoogleTrendsScrapingJob] Unsuccessful scrapes: #{unsuccessful_scrapes}"

      # Accumulate successful and unsuccessful scrapes across all batches in Redis
      redis.incrby(REDIS_SUCCESS_KEY, successful_scrapes)
      redis.incrby(REDIS_UNSUCCESS_KEY, unsuccessful_scrapes)

      # Change VPN only when the last worker of the batch finishes
      if workers_done >= total_workers
        # Reset the counter for future runs
        redis.del(REDIS_WORKERS_KEY)

        # Change VPN only once, after all workers have finished
        GoogleTrendsScraper.new.change_vpn_location
        puts "[GoogleTrendsScrapingJob] VPN changed after all workers in the batch."

        # Log total success and failure counts across all workers and batches
        total_successful_scrapes = redis.get(REDIS_SUCCESS_KEY).to_i
        total_unsuccessful_scrapes = redis.get(REDIS_UNSUCCESS_KEY).to_i
        puts "[GoogleTrendsScrapingJob] Overall Summary for All Batches:"
        puts "[GoogleTrendsScrapingJob] Total Successful scrapes: #{total_successful_scrapes}"
        puts "[GoogleTrendsScrapingJob] Total Unsuccessful scrapes: #{total_unsuccessful_scrapes}"
      end
    rescue => e
      puts "[GoogleTrendsScrapingJob] Error during job execution: #{e.message}"
    ensure
      redis.close
    end
  end
end
