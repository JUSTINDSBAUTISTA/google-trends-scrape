class TrendsController < ApplicationController
  def index
  end

  def fetch_trends
    query = params[:query]

    # List of proxies with valid random ports
    proxies = [
      'http://proxy1.com:8080',
      'http://proxy2.com:3128',
      'http://proxy3.com:8888',
      'http://proxy4.com:1080'
      # Add more proxies with valid ports as needed
    ]

    # Pass proxies to the scraper
    scraper = GoogleTrendsScraper.new(query, proxies)

    # Fetch and export trends data
    scraper.fetch_and_export_trends

    # Notify user that the CSV has been generated
    flash[:notice] = "Google Trends data has been exported to trends_data.csv"
    redirect_to trends_path
  rescue => e
    flash[:alert] = "An error occurred: #{e.message}"
    redirect_to trends_path
  end
end
