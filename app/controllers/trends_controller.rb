class TrendsController < ApplicationController
  def index
    # Display form and existing CSV/ZIP files if necessary
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
