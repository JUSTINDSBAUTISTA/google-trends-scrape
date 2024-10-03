# config/routes.rb
require 'sidekiq/web'

Rails.application.routes.draw do
  # Sidekiq Web UI for monitoring jobs (only enable in development or if properly secured)
  mount Sidekiq::Web => '/sidekiq'

  resources :trends, only: [:index] do
    collection do
      post :fetch_trends
    end
  end

  # Route for serving the ZIP file
  get '/trends_data.zip', to: 'trends#download_zip'
end
