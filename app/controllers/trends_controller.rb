class TrendsController < ApplicationController
  def index
    # Display form and existing CSV/ZIP files if necessary
  end

  def fetch_trends
    queries = params[:queries].split(",")  # Get queries from the form input
    pick_date = params[:pick_date]         # Get selected date range from dropdown

    begin
      scraper = GoogleTrendsScraper.new
  
      # Pass queries and pick_date to the scraper
      scraper.fetch_and_export_trends(queries, pick_date)
  
      flash[:notice] = "Google Trends data fetched successfully!"
    rescue => e
      flash[:alert] = "An error occurred: #{e.message}"
    ensure
      redirect_to trends_path
    end
  end

  def download_zip
    zip_file = Rails.root.join('public', 'trends_data.zip')
    if File.exist?(zip_file)
      send_file(zip_file, type: 'application/zip', filename: 'trends_data.zip', disposition: 'attachment')
    else
      flash[:alert] = "ZIP file not found."
      redirect_to trends_path
    end
  end
end
