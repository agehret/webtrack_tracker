module WebtrackTracker
  class Railtie < Rails::Railtie
    initializer "webtrack_tracker.insert_middleware" do |app|
      app.middleware.use WebtrackTracker::Middleware
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
