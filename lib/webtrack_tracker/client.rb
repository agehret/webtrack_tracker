require "net/http"
require "uri"
require "json"
require "logger"
require "concurrent"

module WebtrackTracker
  class Client
    def self.post_async(api_path, payload)
      config = WebtrackTracker.config
      return unless config.api_key
      return unless tracked_environment?(config)

      if config.debug_mode
        log("[WebtrackTracker] Sending #{api_path} — #{JSON.generate(payload)}")
      end

      Concurrent::Future.execute(executor: :io) do
        response = post(config.endpoint, config.api_key, config.timeout, api_path, payload)
        if config.debug_mode
          if response
            log("[WebtrackTracker] Response: #{response.code}")
          else
            log("[WebtrackTracker] Error: no response received")
          end
        end
        response
      end
    rescue StandardError => e
      log("[WebtrackTracker] Error: #{e.message}") if config.debug_mode
      nil
    end

    private_class_method def self.tracked_environment?(config)
      current = current_env
      config.environments.map(&:to_s).include?(current)
    end

    private_class_method def self.current_env
      if defined?(Rails)
        Rails.env.to_s
      else
        ENV["RACK_ENV"] || ENV["APP_ENV"] || "development"
      end
    end

    private_class_method def self.log(message)
      if defined?(Rails)
        Rails.logger.debug(message)
      else
        @logger ||= Logger.new($stdout)
        @logger.debug(message)
      end
    end

    private_class_method def self.post(base_url, api_key, timeout, api_path, payload)
      uri = URI.parse("#{base_url.to_s.chomp('/')}#{api_path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = timeout
      http.read_timeout = timeout

      request = Net::HTTP::Post.new(uri.path)
      request["X-Api-Key"] = api_key
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)

      http.request(request)
    rescue StandardError
      nil
    end
  end
end
