require "rack"

module WebtrackTracker
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env).tap do |status, _headers, _body|
        request = Rack::Request.new(env)
        track(request) if trackable?(request, status)
      rescue StandardError
        nil
      end
    end

    private

    def trackable?(request, status)
      status.to_i.between?(200, 299) &&
        !ignore?(request.path) &&
        !asset?(request.path) &&
        !bot?(request.user_agent)
    end

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
        ip:        request.ip,
        language:  request.env["HTTP_ACCEPT_LANGUAGE"]
      }
      Client.post_async("/api/track", payload)
    end

    ASSET_PATTERN = /\.(js|css|png|jpg|jpeg|gif|svg|webp|ico|woff|woff2|ttf|eot|map|json|xml|txt)(\?.*)?$/i
    BOT_PATTERN = /bot|crawl|slurp|spider|mediapartners|facebookexternalhit|whatsapp|twitterbot|linkedinbot|embedly|quora|outbrain|pinterestbot|slackbot|vkshare|facebot|ia_archiver|wget|curl|python-requests|java\/|ruby|go-http-client/i

    def asset?(path)
      ASSET_PATTERN.match?(path)
    end

    def bot?(user_agent)
      user_agent.nil? || BOT_PATTERN.match?(user_agent)
    end

  end
end
