require_relative "webtrack_tracker/version"
require_relative "webtrack_tracker/configuration"
require_relative "webtrack_tracker/client"
require_relative "webtrack_tracker/middleware"

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
  end
end

require_relative "webtrack_tracker/railtie" if defined?(Rails::Railtie)
