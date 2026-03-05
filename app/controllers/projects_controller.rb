class ProjectsController < ApplicationController
  def index
    @projects = Project.all
  end

  def show
    @project = Project.find(params[:id])
    unless @project
      redirect_to projects_path, alert: "Project not found."
      return
    end
    @worktrees = GitWorktree.all(@project.path)
    @current_branch = GitWorktree.current_branch(@project.path)
  end

  def new
  end

  def create
    name = Project.sanitize_name(params[:name])
    path = params[:path]&.strip

    if Project.add(name: name, path: path)
      redirect_to projects_path, notice: "Project '#{name}' registered."
    else
      flash.now[:alert] = "Failed to register project. Ensure the name is unique, the path exists, and it's a git repository."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    name = Project.sanitize_name(params[:id])
    if Project.remove(name)
      redirect_to projects_path, notice: "Project '#{name}' removed."
    else
      redirect_to projects_path, alert: "Failed to remove project."
    end
  end
end
