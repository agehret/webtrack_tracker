module WebtrackTracker
  class Railtie < Rails::Railtie
    initializer "webtrack_tracker.insert_middleware" do |app|
      app.middleware.use WebtrackTracker::Middleware

      # ErrorMiddleware has to sit below DebugExceptions — above it Rails has
      # already turned the exception into a 4xx response. Inserted
      # unconditionally: the middleware stack is frozen once initialization is
      # done, and the host app's initializer (config.errortracking) has not run
      # at this point. The middleware checks the config per request instead.
      begin
        app.middleware.insert_after ActionDispatch::DebugExceptions, WebtrackTracker::ErrorMiddleware
      rescue StandardError
        # Apps that removed DebugExceptions: the bottom of the stack is still
        # below ShowExceptions, which is all this needs.
        app.middleware.use WebtrackTracker::ErrorMiddleware
      end
    end

    # Error tracking is opt-in (config.errortracking). Subscribing after
    # initialization ensures the host app's initializer has run; unhandled
    # errors from requests and jobs then flow in via Rails.error.
    config.after_initialize do
      if WebtrackTracker.config.errortracking && defined?(Rails.error)
        Rails.error.subscribe(WebtrackTracker::ErrorSubscriber.new)
      end
    end
  end
end
