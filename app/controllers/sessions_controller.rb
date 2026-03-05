class SessionsController < ApplicationController
  def index
    @sessions = TmuxSession.all
  end

  def show
    name = TmuxSession.sanitize_name(params[:id])
    unless name && TmuxSession.exists?(name)
      redirect_to sessions_path, alert: "Session not found."
      return
    end
    @session_name = name
  end

  def destroy
    name = TmuxSession.sanitize_name(params[:id])
    unless name && TmuxSession.exists?(name)
      redirect_to sessions_path, alert: "Session not found."
      return
    end

    if TmuxSession.kill(name)
      redirect_to sessions_path, notice: "Session '#{name}' removed."
    else
      redirect_to sessions_path, alert: "Failed to remove session '#{name}'."
    end
  end
end
