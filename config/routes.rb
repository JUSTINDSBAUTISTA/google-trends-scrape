# config/routes.rb
Rails.application.routes.draw do
  resources :trends, only: [:index] do
    collection do
      post :fetch_trends
    end
  end

  # Route for serving the ZIP file
  get '/trends_data.zip', to: 'trends#download_zip'
end
