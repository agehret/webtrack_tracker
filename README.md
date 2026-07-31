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
  config.errortracking = false                     # also report application errors to Webtrack
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
| `errortracking` | Boolean | `false` | When `true` (Rails only), application errors are reported to Webtrack via `Rails.error`. See [Error tracking](#error-tracking). |

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

## Error tracking

Set `config.errortracking = true` and the gem subscribes to the [Rails error reporter](https://guides.rubyonrails.org/error_reporting.html) (`Rails.error`). Unhandled exceptions from requests and jobs — plus anything you report manually via `Rails.error.report` — are forwarded to your Webtrack instance, where they are grouped into issues per site (see the "Fehler" tab). New issues and regressions trigger a notification email.

- Reports are fire-and-forget on a background thread; your app never waits and the subscriber never raises.
- The `context` hash is masked with your app's `Rails.application.config.filter_parameters` before it leaves the process.
- Backtraces are run through your app's `Rails.backtrace_cleaner` — the same concise, app-only trace Rails shows on its error pages (framework frames silenced, app frames relative). Errors raised entirely in framework code keep all frames so the trace is never empty.
- Like page views, error reports respect `environments` (default: production only).

Occurrences are automatically enriched with whatever the Rails execution context provides:

- **Request errors** carry `controller` (`PostsController#show`), `method`, `path`, `params` (masked with your `filter_parameters`), `ip`, `user_agent`, `referrer`, `request_id`, and — when the controller responds to `current_user` (Devise and most hand-rolled auth) — `user_id`.
- **Job errors** carry the job class, `job_id`, `queue`, `executions` (attempt count), and the job's arguments in serialized form (models appear as compact `gid://…` URIs, never as attribute dumps).

Anything you add via `Rails.error.set_context` is included as well and takes precedence over the automatic values — use it for data the gem can't know:

```ruby
# e.g. in ApplicationController
before_action do
  Rails.error.set_context(account_id: Current.account&.id)
end
```

Rails only — in plain Rack apps the flag has no effect.

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
