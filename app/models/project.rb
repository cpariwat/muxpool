require "yaml"

class Project
  attr_reader :name, :path

  def initialize(name:, path:)
    @name = name
    @path = path
  end

  def self.config_path
    ENV.fetch("MUXPOOL_PROJECTS_FILE") { Rails.root.join("config", "projects.yml") }
  end

  def self.all
    data = load_config
    (data["projects"] || []).map do |entry|
      new(name: entry["name"], path: entry["path"])
    end
  rescue => e
    Rails.logger.error("Failed to load projects: #{e.message}")
    []
  end

  def self.find(name)
    sanitized = sanitize_name(name)
    all.detect { |p| p.name == sanitized }
  end

  def self.add(name:, path:)
    sanitized = sanitize_name(name)
    return false if sanitized.blank? || path.blank?
    return false unless File.directory?(path)
    return false unless git_repo?(path)
    return false if find(sanitized)

    data = load_config
    data["projects"] ||= []
    data["projects"] << { "name" => sanitized, "path" => File.expand_path(path) }
    save_config(data)
    true
  end

  def self.remove(name)
    sanitized = sanitize_name(name)
    data = load_config
    data["projects"] ||= []
    original_count = data["projects"].length
    data["projects"].reject! { |p| p["name"] == sanitized }
    return false if data["projects"].length == original_count

    save_config(data)
    true
  end

  def self.sanitize_name(name)
    return nil if name.blank?
    name.gsub(/[^a-zA-Z0-9_\-.]/, "").presence
  end

  def self.git_repo?(path)
    File.directory?(File.join(path, ".git"))
  end

  def to_param
    name
  end

  def self.load_config
    return {} unless File.exist?(config_path)
    YAML.safe_load_file(config_path) || {}
  end

  def self.save_config(data)
    File.write(config_path, data.to_yaml)
  end

  private_class_method :load_config, :save_config
end
