require "rack"

module WebtrackTracker
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env).tap do
        request = Rack::Request.new(env)
        track(request) unless ignore?(request.path)
      rescue StandardError
        nil
      end
    end

    private

    def ignore?(path)
      WebtrackTracker.config.ignore_paths.any? do |pattern|
        case pattern
        when Regexp then pattern.match?(path)
        when String then path == pattern
        end
      end
    end

    def track(request)
      payload = {
        path:      request.path,
        referrer:  request.referrer,
        user_agent: request.user_agent,
        ip:        client_ip(request.env),
        language:  request.env["HTTP_ACCEPT_LANGUAGE"]
      }
      Client.post_async("/api/track", payload)
    end

    def client_ip(env)
      forwarded = env["HTTP_X_FORWARDED_FOR"]
      if forwarded && !forwarded.strip.empty?
        forwarded.split(",").first.strip
      else
        env["REMOTE_ADDR"]
      end
    end
  end
end
