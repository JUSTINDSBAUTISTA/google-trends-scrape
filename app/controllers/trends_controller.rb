class TrendsController < ApplicationController
  def index
  end

  def fetch_trends
    query = params[:query]
    scraper = GoogleTrendsScraper.new(query)
    scraper.fetch_and_export_trends
    flash[:notice] = "Google Trends data has been exported to trends_data.csv"
    redirect_to trends_path
  end
end
