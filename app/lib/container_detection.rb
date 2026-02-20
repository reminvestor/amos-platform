# frozen_string_literal: true

module ContainerDetection
  def self.in_container?
    ENV["DOCKER_ENV"].present? ||
      File.exist?("/.dockerenv") ||
      File.exist?("/run/.containerenv")
  end

  def self.web_host
    in_container? ? "web:3000" : "localhost:3000"
  end
end
