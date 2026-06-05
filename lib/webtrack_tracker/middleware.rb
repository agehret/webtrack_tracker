require "rack"

module WebtrackTracker
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      begin
        request = Rack::Request.new(env)
        track(request) if trackable?(request, status, headers)
      rescue StandardError
        nil
      end
      [status, headers, body]
    end

    private

    def trackable?(request, status, headers)
      status.to_i.between?(200, 299) &&
        allowed_environment? &&
        request.get? &&
        !request.xhr? &&
        html_response?(headers) &&
        !ignore?(request.path) &&
        !asset?(request.path) &&
        !bot?(request.user_agent)
    end

    def allowed_environment?
      return true unless defined?(Rails)
      allowed = WebtrackTracker.config.environments.map(&:to_s)
      allowed.include?(Rails.env)
    end

    def html_response?(headers)
      content_type = headers["Content-Type"] || headers["content-type"] || ""
      content_type.include?("text/html")
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
        path:       request.path,
        referrer:   request.referrer,
        user_agent: request.user_agent,
        ip:         request.ip,
        language:   request.env["HTTP_ACCEPT_LANGUAGE"]
      }
      Client.post_async("/api/track", payload)
    end

    ASSET_PATTERN = /\.(js|css|png|jpg|jpeg|gif|svg|webp|ico|woff|woff2|ttf|eot|map|json|xml|txt)(\?.*)?$/i

    BOT_PATTERN = /
      bot|crawl|slurp|spider|mediapartners|
      facebookexternalhit|whatsapp|twitterbot|linkedinbot|
      embedly|quora|outbrain|pinterestbot|slackbot|vkshare|facebot|ia_archiver|
      wget|curl|python-requests|java\/|ruby|go-http-client|
      pingdom|uptimerobot|statuscake|freshping|oh-dear|site24x7|uptimecheck|
      datadog|newrelic|dynatrace|appdynamics|
      nagios|zabbix|prometheus|blackbox|
      googlebot|bingbot|yandex|duckduckbot|
      semrush|ahrefs|moz\.com|majestic
    /xi

    def asset?(path)
      ASSET_PATTERN.match?(path)
    end

    def bot?(user_agent)
      user_agent.nil? || BOT_PATTERN.match?(user_agent)
    end
  end
end
