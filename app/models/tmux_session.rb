require "open3"

class TmuxSession
  attr_reader :name, :windows, :created_at, :attached

  def initialize(name:, windows:, created_at:, attached:)
    @name = name
    @windows = windows
    @created_at = created_at
    @attached = attached
  end

  def self.socket_path
    ENV.fetch("TMUX_SOCKET_PATH", "/tmp/openclaw-tmux-sockets/openclaw.sock")
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

  def self.create(name, start_directory: nil)
    sanitized = sanitize_name(name)
    return false if sanitized.blank?
    return true if exists?(sanitized)

    # Ensure socket directory exists
    FileUtils.mkdir_p(File.dirname(socket_path))

    cmd = [ "tmux", "-S", socket_path, "new-session", "-d", "-s", sanitized ]
    cmd += [ "-c", start_directory ] if start_directory.present?

    _, status = Open3.capture2(*cmd)
    status.success?
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

  def self.sanitize_name(name)
    return nil if name.blank?
    # Only allow alphanumeric, dash, underscore, dot
    sanitized = name.gsub(/[^a-zA-Z0-9_\-.]/, "")
    sanitized.presence
  end

  private

  def self.tmux_command(*args)
    cmd = [ "tmux", "-S", socket_path ] + args
    output, status = Open3.capture2(*cmd)
    output
  end
end
