# frozen_string_literal: true

Rails.application.routes.draw do
  root "projects#index"

  get "/login", to: "sessions#new"
  post "/session", to: "sessions#create"
  delete "/session", to: "sessions#destroy"

  resources :projects, only: %i[index show create update] do
    member do
      get :summary
      get :report, to: "reports#show"
      post :notifications, to: "notifications#create"
      post :exports, to: "exports#create"
    end
  end
  post "/imports", to: "imports#create"
  get "/archived_projects/:id", to: "archived_projects#show", as: :archived_project
  patch "/profile", to: "profiles#update"
  get "/status", to: "status#show"

  namespace :admin do
    resources :projects, only: %i[index] do
      member { post :archive }
    end
  end

  namespace :api do
    resources :projects, only: %i[show]
  end
end
