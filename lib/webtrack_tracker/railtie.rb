module WebtrackTracker
  class Railtie < Rails::Railtie
    initializer "webtrack_tracker.insert_middleware" do |app|
      app.middleware.use WebtrackTracker::Middleware
    end
  end
end
