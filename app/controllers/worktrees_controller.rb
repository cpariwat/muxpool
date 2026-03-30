class WorktreesController < ApplicationController
  before_action :set_project

  def new
    @branches = GitWorktree.branches(@project.path)
    @remote_branches = GitWorktree.remote_branches(@project.path) - @branches
    @default_branch = GitWorktree.default_branch(@project.path)
  end

  def create
    branch_name = params[:branch_name]&.strip
    base_ref = params[:base_ref].presence || GitWorktree.default_branch(@project.path)

    result = GitWorktree.create(@project.path, branch_name: branch_name, base_ref: base_ref)

    if result[:success]
      safe_branch = GitWorktree.sanitize_branch(branch_name).gsub("/", "-")
      session_name = TmuxSession.sanitize_name("#{@project.name}-#{safe_branch}")
      GitWorktree.link_config_files(@project.path, result[:path])
      TmuxSession.create(session_name, start_directory: result[:path])
      install_dependencies(session_name, result[:path])
      redirect_to session_path(session_name)
    else
      flash.now[:alert] = "Failed to create worktree: #{result[:error]}"
      @branches = GitWorktree.branches(@project.path)
      @remote_branches = GitWorktree.remote_branches(@project.path) - @branches
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    worktree = find_worktree(params[:id])
    unless worktree
      redirect_to project_path(@project), alert: "Worktree not found."
      return
    end

    result = GitWorktree.remove(@project.path, worktree.path, force: true)

    if result[:success]
      redirect_to project_path(@project), notice: "Worktree removed."
    else
      redirect_to project_path(@project), alert: "Failed to remove worktree: #{result[:error]}"
    end
  end

  def open_terminal
    worktree = find_worktree(params[:id])
    unless worktree
      redirect_to project_path(@project), alert: "Worktree not found."
      return
    end

    safe_branch = worktree.branch.gsub("/", "-")
    session_name = "#{@project.name}-#{safe_branch}"
    sanitized_name = TmuxSession.sanitize_name(session_name)

    GitWorktree.link_config_files(@project.path, worktree.path)

    if TmuxSession.create(sanitized_name, start_directory: worktree.path)
      redirect_to session_path(sanitized_name)
    else
      redirect_to project_path(@project), alert: "Failed to create terminal session."
    end
  end

  def open_ide
    worktree = find_worktree(params[:id])
    unless worktree
      redirect_to project_path(@project), alert: "Worktree not found."
      return
    end

    result = TmuxSession.open_in_ide(worktree.path)
    if result[:success]
      redirect_to project_path(@project), notice: "Opened #{worktree.branch} in #{TmuxSession.ide_name}."
    else
      redirect_to project_path(@project), alert: "Failed to open IDE: #{result[:error]}"
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
    unless @project
      redirect_to projects_path, alert: "Project not found."
    end
  end

  def find_worktree(basename)
    GitWorktree.all(@project.path).detect { |wt| wt.basename == basename }
  end

  def install_dependencies(session_name, worktree_path)
    commands = []
    commands << "bundle install" if File.exist?(File.join(worktree_path, "Gemfile"))

    if File.exist?(File.join(worktree_path, "yarn.lock"))
      commands << "yarn install"
    elsif File.exist?(File.join(worktree_path, "pnpm-lock.yaml"))
      commands << "pnpm install"
    elsif File.exist?(File.join(worktree_path, "package-lock.json"))
      commands << "npm install"
    end

    return if commands.empty?

    TmuxSession.send_keys(session_name, commands.join(" && "))
  end
end
