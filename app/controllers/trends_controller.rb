class TrendsController < ApplicationController
  def index
  end

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
      scraper.fetch_and_export_trends
      flash[:notice] = "Google Trends data has been exported to trends_data.csv"
    rescue => e
      flash[:alert] = "An error occurred: #{e.message}"
    end

    redirect_to trends_path
  end
end
