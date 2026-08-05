require_relative "webtrack_tracker/version"
require_relative "webtrack_tracker/configuration"
require_relative "webtrack_tracker/client"
require_relative "webtrack_tracker/middleware"
require_relative "webtrack_tracker/error_middleware"
require_relative "webtrack_tracker/error_subscriber"

module WebtrackTracker
  class << self
    def configure
      yield config
    end

    def config
      @config ||= Configuration.new
    end

    def track_event(name, path:, meta: {}, user_agent: nil, ip: nil)
      payload = { name: name, path: path, meta: meta }
      payload[:user_agent] = user_agent if user_agent
      payload[:ip] = ip if ip
      Client.post_async("/api/event", payload)
    end

    # Reports a successful cron job run to the matching Webtrack check-in.
    # Pass a name configured in config.checkins, or a raw token via token:.
    # Unlike the tracking calls this is synchronous — cron processes exit right
    # after the ping, so a background thread could be killed mid-request.
    # Returns true/false and never raises.
    def ping(name = nil, token: nil)
      token ||= config.checkins[name.to_sym] || config.checkins[name.to_s] if name
      Client.ping(token, checkin: name)
    end
  end
end

require_relative "webtrack_tracker/railtie" if defined?(Rails::Railtie)
