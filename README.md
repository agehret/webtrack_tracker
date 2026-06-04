# WebtrackTracker

Rack middleware for non-blocking page-view tracking via [Webtrack](https://github.com/agehret/webtrack_tracker). Each request is forwarded to the Webtrack API asynchronously on a background thread, so there is no latency added to your responses.

## Requirements

- Ruby >= 3.0
- Rack >= 2.0

## Installation

Add to your Gemfile:

```ruby
gem "webtrack_tracker", github: "agehret/webtrack_tracker", tag: "v0.1.0"
```

Then run:

```
bundle install
```

## Configuration

Create an initializer (e.g. `config/initializers/webtrack_tracker.rb`):

```ruby
WebtrackTracker.configure do |config|
  config.api_key      = ENV["WEBTRACK_API_KEY"]   # required
  config.endpoint     = "https://your-webtrack-instance.com"  # default shown
  config.timeout      = 5          # HTTP timeout in seconds (default: 5)
  config.ignore_paths = [          # paths/patterns to skip tracking
    "/health",
    /\A\/assets\//
  ]
end
```

| Option | Type | Default | Description |
|---|---|---|---|
| `api_key` | String | `nil` | Your Webtrack API key. Tracking is disabled when blank. |
| `endpoint` | String | `https://webtrack.example.com` | Base URL of your Webtrack instance. |
| `timeout` | Integer | `5` | Open/read timeout in seconds for the tracking request. |
| `ignore_paths` | Array | `[]` | Strings (exact match) or Regexps to exclude from tracking. |

## Rails

The gem ships a Railtie that automatically inserts the middleware when Rails is present. No manual wiring needed — configure it in an initializer as shown above and you're done.

## Non-Rails Rack apps

Insert the middleware manually in your `config.ru`:

```ruby
require "webtrack_tracker"

WebtrackTracker.configure do |config|
  config.api_key   = ENV["WEBTRACK_API_KEY"]
  config.endpoint  = "https://your-webtrack-instance.com"
end

use WebtrackTracker::Middleware
run MyApp
```

## Tracking custom events

Call `WebtrackTracker.track_event` anywhere in your application to record a named event:

```ruby
WebtrackTracker.track_event(
  "signup",
  path:       "/registrations",
  meta:       { plan: "pro" },
  user_agent: request.user_agent,
  ip:         request.remote_ip
)
```

| Parameter | Required | Description |
|---|---|---|
| `name` | yes | Event name (e.g. `"signup"`, `"purchase"`). |
| `path:` | yes | Path associated with the event. |
| `meta:` | no | Hash of arbitrary metadata to attach to the event. |
| `user_agent:` | no | User-Agent string of the visitor. |
| `ip:` | no | IP address of the visitor. |

All tracking calls are fire-and-forget — errors are silently swallowed so they never affect your application.

## License

[MIT](https://opensource.org/licenses/MIT)
