require "rack"
require "ipaddr"
require "uri"

module WebtrackTracker
  class Middleware
    def initialize(app)
      @app = app
    end

    OPT_OUT_PATH = "/webtrack/opt-out"
    OPT_IN_PATH  = "/webtrack/opt-in"

    def call(env)
      request = Rack::Request.new(env)
      return handle_opt_out(request) if opt_out_path?(request.path)

      status, headers, body = @app.call(env)
      begin
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
        !prefetch?(request) &&
        !ignore?(request.path) &&
        !ignore_ip?(request.ip) &&
        !ignore_referrer_ip?(request.referrer) &&
        !opt_out_cookie?(request) &&
        !asset?(request.path) &&
        !bot?(request.user_agent)
    end

    def prefetch?(request)
      env = request.env
      env["HTTP_SEC_PURPOSE"] == "prefetch" ||
        env["HTTP_PURPOSE"]   == "prefetch"
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

    def ignore_ip?(ip)
      return false if ip.nil? || ip.empty?
      request_addr = parse_ip(ip)
      return false unless request_addr
      WebtrackTracker.config.ignore_ips.any? do |entry|
        configured = parse_ip(entry)
        next false unless configured
        configured == request_addr || configured.include?(request_addr)
      rescue IPAddr::InvalidAddressError
        false
      end
    end

    def parse_ip(ip)
      addr = IPAddr.new(ip.to_s.strip)
      addr.ipv4_mapped? ? IPAddr.new(addr.native.to_s) : addr
    rescue IPAddr::InvalidAddressError
      nil
    end

    def ignore_referrer_ip?(referrer)
      return false if referrer.nil? || referrer.empty?
      host = URI.parse(referrer).host
      host && ignore_ip?(host)
    rescue URI::InvalidURIError
      false
    end

    def opt_out_cookie?(request)
      cookie_name = WebtrackTracker.config.ignore_cookie
      cookie_name && request.cookies.key?(cookie_name)
    end

    def opt_out_path?(path)
      path == OPT_OUT_PATH || path == OPT_IN_PATH
    end

    def handle_opt_out(request)
      response = Rack::Response.new
      cookie_name = WebtrackTracker.config.ignore_cookie
      if request.path == OPT_OUT_PATH
        response.set_cookie(cookie_name, value: "1", path: "/", expires: Time.now + (10 * 365 * 24 * 60 * 60), httponly: true)
      else
        response.delete_cookie(cookie_name, path: "/")
      end
      redirect_to = request.params["return_to"] || request.referer || "/"
      response.redirect(redirect_to)
      response.finish
    end

    UTM_KEYS = %w[utm_source utm_medium utm_campaign utm_term utm_content].freeze

    def track(request)
      payload = {
        path:       request.path,
        referrer:   request.referrer,
        user_agent: request.user_agent,
        ip:         request.ip,
        language:   request.env["HTTP_ACCEPT_LANGUAGE"]
      }.merge(utm_params(request))
      Client.post_async("/api/track", payload)
    end

    def utm_params(request)
      UTM_KEYS.each_with_object({}) do |key, acc|
        value = request.params[key]
        acc[key.to_sym] = value if value.is_a?(String) && !value.empty?
      end
    rescue StandardError
      {}
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
