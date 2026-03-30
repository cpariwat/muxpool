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
    @sessions = TmuxSession.all
  end

  def update
    old_name = TmuxSession.sanitize_name(params[:id])
    new_name = TmuxSession.sanitize_name(params[:name])

    unless old_name && TmuxSession.exists?(old_name)
      redirect_to sessions_path, alert: "Session not found."
      return
    end

    if new_name.blank?
      redirect_to session_path(old_name), alert: "Invalid session name."
    elsif TmuxSession.rename(old_name, new_name)
      redirect_to session_path(new_name), notice: "Session renamed to '#{new_name}'."
    else
      redirect_to session_path(old_name), alert: "Failed to rename session. Name may already be taken."
    end
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

  def open_ide
    name = TmuxSession.sanitize_name(params[:id])
    unless name && TmuxSession.exists?(name)
      redirect_to sessions_path, alert: "Session not found."
      return
    end

    directory = TmuxSession.pane_current_path(name)
    unless directory
      redirect_back fallback_location: session_path(name), alert: "Could not determine session working directory."
      return
    end

    result = TmuxSession.open_in_ide(directory)
    if result[:success]
      redirect_back fallback_location: session_path(name), notice: "Opened #{directory} in #{TmuxSession.ide_name}."
    else
      redirect_back fallback_location: session_path(name), alert: "Failed to open IDE: #{result[:error]}"
    end
  end
end
