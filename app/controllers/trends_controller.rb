class TrendsController < ApplicationController
  def index
  end

  def fetch_trends
    query = params[:query]

    # List of proxies
    proxies = [
      'http://proxy1:port',
      'http://proxy2:port',
      'http://proxy3:port'
      # Add more proxies as needed
    ]

    # Pass proxies to the scraper
    scraper = GoogleTrendsScraper.new(query, proxies)

    # Fetch and export trends data
    scraper.fetch_and_export_trends

    # Notify user that the CSV has been generated
    flash[:notice] = "Google Trends data has been exported to trends_data.csv"
    redirect_to trends_path
  end
end
