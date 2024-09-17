# app/services/the_tvdb_api_service.rb
require 'httparty'

class TheTVDBApiService
  include HTTParty
  base_uri 'https://api4.thetvdb.com/v4'

  def initialize
    @options = {
      headers: {
        "Authorization" => "Bearer #{ENV['TVDB_BEARER_TOKEN']}",
        "Content-Type" => "application/json"
      }
    }
  end

  def get_series(series_id)
    self.class.get("/series/#{series_id}", @options)
  end
end
