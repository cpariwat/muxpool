class AuthController < ApplicationController
  skip_before_action :require_authentication, only: [ :login, :authenticate ]

  # Rate limiting: max 5 login attempts per minute per IP
  rate_limit to: 5, within: 1.minute, only: :authenticate, with: -> {
    redirect_to login_path, alert: "Too many login attempts. Please wait a moment."
  }

  def login
    redirect_to sessions_path if session[:authenticated]
  end

  def authenticate
    if password_matches?(params[:password])
      reset_session
      session[:authenticated] = true
      redirect_to sessions_path, notice: "Logged in successfully."
    else
      redirect_to login_path, alert: "Invalid password."
    end
  end

  def logout
    reset_session
    redirect_to login_path, notice: "Logged out."
  end

  private

  def password_matches?(input)
    return false if input.blank?

    stored = admin_password
    ActiveSupport::SecurityUtils.secure_compare(input, stored)
  end
end
