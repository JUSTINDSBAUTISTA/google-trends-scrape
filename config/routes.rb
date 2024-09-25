Rails.application.routes.draw do
  resources :trends, only: [:index] do
    collection do
      post :fetch_trends
    end
  end
end
