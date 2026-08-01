require "net/http"
require "uri"
require "json"
require "logger"
require "concurrent"

module WebtrackTracker
  class Client
    # A lost ping means a false alarm in Webtrack, so network errors and 5xx
    # responses are retried; 4xx (bad token) is final and never retried.
    PING_ATTEMPTS = 3
    PING_RETRY_DELAY = 1

    def self.ping(token, checkin: nil)
      config = WebtrackTracker.config
      if token.to_s.empty?
        log("[WebtrackTracker] Ping skipped: no token#{checkin ? " for check-in #{checkin.inspect}" : ""} — set config.checkins")
        return false
      end
      unless URI.parse(config.endpoint.to_s).scheme == "https"
        log("[WebtrackTracker] Ping skipped: endpoint must use HTTPS (got: #{config.endpoint})")
        return false
      end
      unless tracked_environment?(config)
        log("[WebtrackTracker] Ping skipped: environment not tracked") if config.debug_mode
        return false
      end

      uri = URI.parse("#{config.endpoint.to_s.chomp('/')}/ping/#{URI.encode_www_form_component(token)}")

      PING_ATTEMPTS.times do |attempt|
        sleep(PING_RETRY_DELAY) if attempt.positive?
        response = get(uri, config.timeout)

        if response.is_a?(Net::HTTPSuccess)
          log("[WebtrackTracker] Ping #{uri.path}: #{response.code}") if config.debug_mode
          return true
        end

        log("[WebtrackTracker] Ping attempt #{attempt + 1} failed (#{response ? response.code : "no response"})") if config.debug_mode
        return false if response.is_a?(Net::HTTPClientError)
      end

      false
    rescue StandardError => e
      log("[WebtrackTracker] Ping error: #{e.message}") if config.debug_mode
      false
    end

    def self.post_async(api_path, payload)
      config = WebtrackTracker.config
      unless config.api_key
        log("[WebtrackTracker] Tracking skipped: api_key is not configured")
        return
      end
      unless URI.parse(config.endpoint.to_s).scheme == "https"
        log("[WebtrackTracker] Tracking skipped: endpoint must use HTTPS (got: #{config.endpoint})")
        return
      end
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

    private_class_method def self.get(uri, timeout)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.request(Net::HTTP::Get.new(uri.path))
    rescue StandardError
      nil
    end

    private_class_method def self.post(base_url, api_key, timeout, api_path, payload)
      uri = URI.parse("#{base_url.to_s.chomp('/')}#{api_path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
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
