class TrendsController < ApplicationController
  def fetch_trends
    queries = params[:queries].to_s.split(',').map(&:strip) # Split the queries by comma and remove whitespace

    if queries.empty?
      flash[:alert] = "Queries parameter is missing."
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

    # Create a hash to store filenames for each query
    filenames = {}

    queries.each do |query|
      scraper = GoogleTrendsScraper.new(query, email, password)
      
      begin
        filename = "#{query.parameterize}.csv" # Set the filename based on the query
        filenames[query] = filename
        scraper.fetch_and_export_trends(filename)
      rescue => e
        flash[:alert] = "An error occurred for query '#{query}': #{e.message}"
        next
      end
    end

    flash[:notice] = "Google Trends data has been exported."
    flash[:filenames] = filenames # Store the filenames in flash for later retrieval
    redirect_to trends_path
  end
end
