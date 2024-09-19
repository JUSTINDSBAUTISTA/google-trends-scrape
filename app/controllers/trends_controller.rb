class TrendsController < ApplicationController
  def fetch_trends
    queries = params[:queries].to_s.split(',').map(&:strip)
    puts "Queries count: #{queries.size}"
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
  
    # Create an instance of GoogleTrendsScraper with the correct number of arguments
    scraper = GoogleTrendsScraper.new(email, password)
    scraper.fetch_and_export_trends(queries)
  
    flash[:notice] = "Google Trends data has been exported."
    redirect_to trends_path
  end
  
end
