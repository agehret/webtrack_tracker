# WebtrackTracker

Rack middleware for non-blocking page-view tracking via [Webtrack](https://github.com/agehret/webtrack_tracker). Each request is forwarded to the Webtrack API asynchronously on a background thread, so there is no latency added to your responses.

## Requirements

- Ruby >= 3.0
- Rack >= 2.0

## Installation

Add to your Gemfile:

```ruby
gem "webtrack_tracker", github: "agehret/webtrack_tracker", tag: "v0.2.4"
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
  config.endpoint     = "https://your-webtrack-instance.com"
  config.environments = [:production]              # environments in which tracking is active
  config.timeout      = 5                          # HTTP timeout in seconds
  config.debug_mode   = false                      # log requests and responses
  config.ignore_paths  = [                         # paths/patterns to skip tracking
    "/health",
    /\A\/assets\//
  ]
  config.ignore_ips    = ["192.168.1.1"]           # IP addresses to exclude from tracking
  config.ignore_cookie = "webtrack_exclude"        # cookie name for browser-level opt-out
end
```

| Option | Type | Default | Description |
|---|---|---|---|
| `api_key` | String | `nil` | Your Webtrack API key. Tracking is disabled when blank. |
| `endpoint` | String | `https://webtrack.example.com` | Base URL of your Webtrack instance. |
| `environments` | Array | `[:production]` | Environments in which tracking is active. Uses `Rails.env` in Rails apps, otherwise `RACK_ENV` / `APP_ENV`. |
| `timeout` | Integer | `5` | Open/read timeout in seconds for the tracking request. |
| `debug_mode` | Boolean | `false` | When `true`, logs each request payload and the HTTP response code with a `[WebtrackTracker]` prefix. Uses `Rails.logger` in Rails, `$stdout` otherwise. |
| `ignore_paths` | Array | `[]` | Strings (exact match) or Regexps to exclude from tracking. |
| `ignore_ips` | Array | `[]` | IP addresses to exclude from tracking. |
| `ignore_cookie` | String | `"webtrack_exclude"` | Cookie name for browser-level opt-out. Set to `nil` to disable. |

## Excluding your own traffic

Visit `/webtrack/opt-out` in your browser to set a persistent opt-out cookie. Any browser carrying that cookie will be excluded from tracking regardless of IP or environment.

To re-enable tracking for your browser, visit `/webtrack/opt-in`.

These routes are handled by the middleware itself — no changes to `routes.rb` are needed.

The cookie name defaults to `webtrack_exclude` and can be customised:

```ruby
config.ignore_cookie = "my_opt_out"
```

Set `ignore_cookie` to `nil` to disable the opt-out routes and cookie check entirely.

You can also exclude specific IP addresses:

```ruby
config.ignore_ips = ["203.0.113.42"]
```

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

## UTM parameters

Page views automatically capture the five standard UTM parameters when present in the request query string:

- `utm_source`
- `utm_medium`
- `utm_campaign`
- `utm_term`
- `utm_content`

For example, a visit to `/landing?utm_source=google&utm_medium=cpc&utm_campaign=spring` forwards those values to Webtrack alongside the page view, where they are used for channel attribution and campaign reporting. Only these keys are extracted — arbitrary query parameters are never forwarded, keeping potentially sensitive query data out of the tracking payload.

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
