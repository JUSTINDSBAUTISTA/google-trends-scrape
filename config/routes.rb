Rails.application.routes.draw do
  get 'trends', to: 'trends#index'
  post 'trends/fetch', to: 'trends#fetch_trends'
end
