Rails.application.routes.draw do
  # Authentication
  get  "login",  to: "auth#login",        as: :login
  post "login",  to: "auth#authenticate", as: :authenticate
  get  "logout", to: "auth#logout",       as: :logout

  # Sessions (tmux)
  resources :sessions, only: [ :index, :show, :update, :destroy ]

  # Projects & Worktrees
  resources :projects, only: [ :index, :show, :new, :create, :destroy ] do
    resources :worktrees, only: [ :new, :create, :destroy ] do
      member do
        post :open_terminal
      end
    end
  end

  # Root
  root "sessions#index"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
