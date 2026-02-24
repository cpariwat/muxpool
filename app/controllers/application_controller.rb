class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :require_authentication

  private

  def require_authentication
    unless session[:authenticated]
      redirect_to login_path
    end
  end

  def admin_password
    ENV.fetch("TMUX_WEB_PASSWORD", "admin")
  end
end
