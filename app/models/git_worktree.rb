require "open3"

class GitWorktree
  attr_reader :path, :branch, :head, :bare, :detached, :prunable
  attr_accessor :main

  def initialize(path:, branch:, head:, bare: false, detached: false, prunable: false, main: false)
    @path = path
    @branch = branch
    @head = head
    @bare = bare
    @detached = detached
    @prunable = prunable
    @main = main
  end

  def self.all(project_path)
    output, status = Open3.capture2("git", "-C", project_path, "worktree", "list", "--porcelain")
    return [] unless status.success?

    parse_porcelain(output)
  rescue => e
    Rails.logger.error("Failed to list worktrees for #{project_path}: #{e.message}")
    []
  end

  def self.create(project_path, branch_name:, base_ref: "HEAD", worktree_path: nil)
    sanitized = sanitize_branch(branch_name)
    return { success: false, error: "Invalid branch name" } if sanitized.blank?

    wt_path = worktree_path || default_worktree_path(project_path, sanitized)

    if branch_exists?(project_path, sanitized)
      # Branch exists locally or remotely — git auto-creates tracking branch
      _, err, status = Open3.capture3(
        "git", "-C", project_path, "worktree", "add", wt_path, sanitized
      )
    else
      # New branch — create from base_ref
      base_ref = default_branch(project_path) if base_ref == "HEAD"
      _, err, status = Open3.capture3(
        "git", "-C", project_path, "worktree", "add", "-b", sanitized, wt_path, base_ref
      )
    end

    if status.success?
      { success: true, path: wt_path }
    else
      { success: false, error: err.strip.presence || "Unknown error" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  # Directories to skip when symlinking gitignored files (bulk/generated content)
  IGNORED_LINK_DIRS = %w[
    node_modules tmp log vendor/bundle coverage storage
    public/assets public/packs public/vite
    .idea .ruby-lsp .spec-workflow .claude .git
  ].freeze

  def self.link_config_files(source_path, worktree_path)
    linked = []

    gitignored_files(source_path).each do |relative|
      source_file = File.join(source_path, relative)
      target = File.join(worktree_path, relative)

      next unless File.file?(source_file)
      next if File.exist?(target) || File.symlink?(target)

      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.ln_s(source_file, target)
      linked << relative
    end

    linked
  rescue => e
    Rails.logger.error("Failed to link config files: #{e.message}")
    linked
  end

  def self.gitignored_files(project_path)
    output, status = Open3.capture2(
      "git", "-C", project_path,
      "ls-files", "--others", "--ignored", "--exclude-standard"
    )
    return [] unless status.success?

    output.strip.split("\n").reject do |path|
      IGNORED_LINK_DIRS.any? { |dir| path.start_with?("#{dir}/") }
    end
  rescue => e
    Rails.logger.error("Failed to list gitignored files: #{e.message}")
    []
  end

  private_class_method :gitignored_files

  def self.remove(project_path, worktree_path, force: false)
    args = ["git", "-C", project_path, "worktree", "remove"]
    args << "--force" if force
    args << worktree_path

    _, err, status = Open3.capture3(*args)
    if status.success?
      { success: true }
    else
      { success: false, error: err.strip.presence || "Unknown error" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  def self.branch_exists?(project_path, branch_name)
    # Check local
    _, status = Open3.capture2("git", "-C", project_path, "rev-parse", "--verify", "refs/heads/#{branch_name}")
    return true if status.success?

    # Check remote
    _, status = Open3.capture2("git", "-C", project_path, "rev-parse", "--verify", "refs/remotes/origin/#{branch_name}")
    status.success?
  rescue
    false
  end

  def self.remote_branches(project_path)
    output, status = Open3.capture2("git", "-C", project_path, "branch", "-r", "--format=%(refname:short)")
    return [] unless status.success?

    output.strip.split("\n")
      .map { |b| b.strip.sub("origin/", "") }
      .reject { |b| b.blank? || b.include?("HEAD") }
  rescue => e
    Rails.logger.error("Failed to list remote branches for #{project_path}: #{e.message}")
    []
  end

  def self.branches(project_path)
    output, status = Open3.capture2("git", "-C", project_path, "branch", "--format=%(refname:short)")
    return [] unless status.success?

    output.strip.split("\n").map(&:strip).reject(&:blank?)
  rescue => e
    Rails.logger.error("Failed to list branches: #{e.message}")
    []
  end

  def self.current_branch(project_path)
    output, status = Open3.capture2("git", "-C", project_path, "rev-parse", "--abbrev-ref", "HEAD")
    return nil unless status.success?

    output.strip.presence
  rescue
    nil
  end

  def self.default_branch(project_path)
    # Try symbolic-ref to origin/HEAD first (most reliable for remote default)
    output, status = Open3.capture2("git", "-C", project_path, "symbolic-ref", "refs/remotes/origin/HEAD", "--short")
    if status.success?
      branch = output.strip.sub("origin/", "")
      return branch if branch.present?
    end

    # Fall back to checking common default branch names
    %w[main master development develop].each do |candidate|
      _, status = Open3.capture2("git", "-C", project_path, "rev-parse", "--verify", "refs/heads/#{candidate}")
      return candidate if status.success?
    end

    # Last resort: current HEAD
    current_branch(project_path) || "HEAD"
  rescue
    "HEAD"
  end

  def self.sanitize_branch(name)
    return nil if name.blank?
    name.gsub(/[^a-zA-Z0-9_\-.\/ ]/, "").strip.presence
  end

  def basename
    File.basename(path)
  end

  def to_param
    basename
  end

  def main_worktree?
    @main || bare
  end

  def self.default_worktree_path(project_path, branch_name)
    repo_name = File.basename(project_path)
    safe_branch = branch_name.gsub("/", "-")
    File.join(File.dirname(project_path), "#{repo_name}-worktrees", safe_branch)
  end

  private_class_method :default_worktree_path

  def self.parse_porcelain(output)
    worktrees = []
    current = {}

    output.each_line do |line|
      line = line.chomp
      if line.empty?
        worktrees << build_worktree(current) if current[:path]
        current = {}
      elsif line.start_with?("worktree ")
        current[:path] = line.sub("worktree ", "")
      elsif line.start_with?("HEAD ")
        current[:head] = line.sub("HEAD ", "")
      elsif line.start_with?("branch ")
        current[:branch] = line.sub("branch refs/heads/", "")
      elsif line == "bare"
        current[:bare] = true
      elsif line == "detached"
        current[:detached] = true
      elsif line == "prunable"
        current[:prunable] = true
      end
    end

    worktrees << build_worktree(current) if current[:path]

    # First worktree is always the main one
    worktrees.first.main = true if worktrees.any?
    worktrees
  end

  private_class_method :parse_porcelain

  def self.build_worktree(data)
    new(
      path: data[:path],
      branch: data[:branch] || "(detached)",
      head: data[:head] || "",
      bare: data[:bare] || false,
      detached: data[:detached] || false,
      prunable: data[:prunable] || false
    )
  end

  private_class_method :build_worktree
end
