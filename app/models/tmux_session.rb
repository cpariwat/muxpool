require "open3"
require "shellwords"

class TmuxSession
  attr_reader :name, :windows, :created_at, :attached

  def initialize(name:, windows:, created_at:, attached:)
    @name = name
    @windows = windows
    @created_at = created_at
    @attached = attached
  end

  def self.socket_path
    ENV.fetch("TMUX_SOCKET_PATH", "/tmp/muxpool-tmux/default.sock")
  end

  def self.all
    output = tmux_command("list-sessions", "-F", '#{session_name}|#{session_windows}|#{session_created}|#{session_attached}')
    return [] if output.blank?

    output.strip.split("\n").map do |line|
      parts = line.split("|")
      next if parts.length < 4

      new(
        name: parts[0],
        windows: parts[1].to_i,
        created_at: Time.at(parts[2].to_i),
        attached: parts[3].to_i > 0
      )
    end.compact
  rescue => e
    Rails.logger.error("Failed to list tmux sessions: #{e.message}")
    []
  end

  def self.exists?(name)
    sanitized = sanitize_name(name)
    return false if sanitized.blank?

    cmd = [ "tmux", "-S", socket_path, "has-session", "-t", "=#{sanitized}" ]
    _, status = Open3.capture2(*cmd)
    status.success?
  rescue
    false
  end

  BUNDLER_VARS = %w[
    BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_APP_CONFIG
    RUBYOPT RUBYLIB GEM_HOME GEM_PATH
  ].freeze

  def self.create(name, start_directory: nil)
    sanitized = sanitize_name(name)
    return false if sanitized.blank?
    return true if exists?(sanitized)

    # Ensure socket directory exists
    FileUtils.mkdir_p(File.dirname(socket_path))

    cmd = [ "tmux", "-S", socket_path, "new-session", "-d", "-s", sanitized ]
    cmd += [ "-c", start_directory ] if start_directory.present?

    Bundler.with_unbundled_env do
      _, status = Open3.capture2(*cmd)
      return false unless status.success?
    end

    # Remove Bundler vars from the tmux session environment and the running shell.
    # The tmux server may have inherited the host app's env, so new sessions
    # inherit those vars even when the client env is clean.
    clean_session_environment(sanitized)
    true
  rescue => e
    Rails.logger.error("Failed to create tmux session '#{sanitized}': #{e.message}")
    false
  end

  def self.rename(old_name, new_name)
    old_sanitized = sanitize_name(old_name)
    new_sanitized = sanitize_name(new_name)
    return false if old_sanitized.blank? || new_sanitized.blank?
    return false unless exists?(old_sanitized)
    return false if exists?(new_sanitized)

    cmd = [ "tmux", "-S", socket_path, "rename-session", "-t", "=#{old_sanitized}", new_sanitized ]
    _, status = Open3.capture2(*cmd)
    status.success?
  rescue => e
    Rails.logger.error("Failed to rename tmux session '#{old_sanitized}' to '#{new_sanitized}': #{e.message}")
    false
  end

  def self.kill(name)
    sanitized = sanitize_name(name)
    return false if sanitized.blank?

    cmd = [ "tmux", "-S", socket_path, "kill-session", "-t", "=#{sanitized}" ]
    _, status = Open3.capture2(*cmd)
    status.success?
  rescue => e
    Rails.logger.error("Failed to kill tmux session '#{sanitized}': #{e.message}")
    false
  end

  def self.send_keys(name, keys)
    sanitized = sanitize_name(name)
    return false if sanitized.blank?

    cmd = [ "tmux", "-S", socket_path, "send-keys", "-t", "=#{sanitized}", keys, "Enter" ]
    _, status = Open3.capture2(*cmd)
    status.success?
  rescue => e
    Rails.logger.error("Failed to send keys to tmux session '#{sanitized}': #{e.message}")
    false
  end

  def self.pane_current_path(name)
    sanitized = sanitize_name(name)
    return nil if sanitized.blank?

    output, status = Open3.capture2("tmux", "-S", socket_path, "list-panes", "-t", "=#{sanitized}", "-F", '#{pane_current_path}', "-f", '#{pane_active}')
    return nil unless status.success?

    path = output.lines.first&.strip
    path.presence
  rescue => e
    Rails.logger.error("Failed to get pane path for '#{name}': #{e.message}")
    nil
  end

  def self.ide_command(directory)
    cmd_str = ENV.fetch("MUXPOOL_IDE_COMMAND", "open -a RubyMine")
    Shellwords.shellsplit(cmd_str) + [ directory ]
  end

  def self.ide_name
    cmd = ENV.fetch("MUXPOOL_IDE_COMMAND", "open -a RubyMine")
    if cmd.include?("RubyMine")
      "RubyMine"
    elsif cmd.include?("cursor")
      "Cursor"
    elsif cmd.include?("code")
      "VS Code"
    else
      "IDE"
    end
  end

  def self.open_in_ide(directory)
    return { success: false, error: "No directory provided" } if directory.blank?
    return { success: false, error: "Directory does not exist" } unless File.directory?(directory)

    cmd = ide_command(directory)
    output, status = Open3.capture2e(*cmd)

    if status.success?
      { success: true }
    else
      { success: false, error: output.strip.presence || "IDE command failed" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  def self.sanitize_name(name)
    return nil if name.blank?
    # Only allow alphanumeric, dash, underscore, dot
    sanitized = name.gsub(/[^a-zA-Z0-9_\-.]/, "")
    sanitized.presence
  end

  private

  def self.clean_session_environment(sanitized)
    BUNDLER_VARS.each do |var|
      # Unset from tmux server global env
      Open3.capture2("tmux", "-S", socket_path, "set-environment", "-g", "-u", var)
      # Unset from session env
      Open3.capture2("tmux", "-S", socket_path, "set-environment", "-t", "=#{sanitized}", "-u", var)
    end

    # Unset vars in the already-running shell and clear the screen
    unset_cmd = "unset #{BUNDLER_VARS.join(' ')} && clear"
    Open3.capture2("tmux", "-S", socket_path, "send-keys", "-t", "=#{sanitized}", unset_cmd, "Enter")
  rescue => e
    Rails.logger.error("Failed to clean session environment: #{e.message}")
  end

  def self.tmux_command(*args)
    cmd = [ "tmux", "-S", socket_path ] + args
    output, status = Open3.capture2(*cmd)
    output
  end
end
