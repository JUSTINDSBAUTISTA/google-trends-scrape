# app/controllers/series_controller.rb
class SeriesController < ApplicationController
  def show
    series_id = params[:id]
    tvdb_service = TheTVDBApiService.new
    @series = tvdb_service.get_series(series_id)

    if @series.success?
      render json: @series.parsed_response
    else
      render json: { error: 'Failed to fetch series data' }, status: :unprocessable_entity
    end
  end
end
