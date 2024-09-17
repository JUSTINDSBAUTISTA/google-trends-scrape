class TrendsController < ApplicationController
  def fetch_trends
    query = params[:query]

    if query.blank?
      flash[:alert] = "Query parameter is missing."
      redirect_to trends_path
      return
    end

    email = ENV['GOOGLE_TRENDS_EMAIL']
    password = ENV['GOOGLE_TRENDS_PASSWORD']

    if email.blank? || password.blank?
      flash[:alert] = "Google account credentials are missing."
      redirect_to trends_path
      return
    end

    scraper = GoogleTrendsScraper.new(query, email, password)

    begin
      filename = "#{query}.csv" # Set the filename based on the query
      scraper.fetch_and_export_trends(filename) # Pass the filename to the scraper
      flash[:notice] = "Google Trends data has been exported to '#{filename}'"
      flash[:filename] = filename # Store the filename in flash for later retrieval
    rescue => e
      flash[:alert] = "An error occurred: #{e.message}"
    end

    redirect_to trends_path
  end
end
