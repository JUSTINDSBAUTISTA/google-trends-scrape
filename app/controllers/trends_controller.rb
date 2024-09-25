class TrendsController < ApplicationController
  def index
    # Display form and existing CSV files if necessary
  end

  def fetch_trends
    queries = params[:queries].split(",")  # Get queries from the form input
  
    begin
      scraper = GoogleTrendsScraper.new
  
      # Call the fetch_and_export_trends method in the scraper, defaulting to 5 pages
      scraper.fetch_and_export_trends(queries)
  
      flash[:notice] = "Google Trends data fetched successfully!"
    rescue => e
      flash[:alert] = "An error occurred: #{e.message}"
    ensure
      redirect_to trends_path
    end
  end
end
