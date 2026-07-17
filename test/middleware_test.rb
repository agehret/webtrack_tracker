require "test_helper"

class MiddlewareTest < Minitest::Test
  HTML_APP  = ->(_env) { [200, { "Content-Type" => "text/html; charset=utf-8" }, ["<html>"]] }
  DUMMY_APP = HTML_APP
  JSON_APP  = ->(_env) { [200, { "Content-Type" => "application/json" }, ['{"ok":true}']] }

  def setup
    super
    WebtrackTracker.configure do |c|
      c.api_key      = "test-key"
      c.ignore_paths = [%r{\A/assets/}, "/up"]
    end
  end

  def test_passes_through_app_response
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    WebtrackTracker::Client.stub(:post_async, nil) do
      status, _headers, body = middleware.call(env_for("/"))
      assert_equal 200, status
      assert_equal ["<html>"], body
    end
  end

  def test_tracks_regular_path
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(path, payload) { captured << [path, payload] }) do
      middleware.call(env_for("/about"))
    end

    assert_equal 1, captured.size
    assert_equal "/api/track", captured.first[0]
    assert_equal "/about", captured.first[1][:path]
  end

  def test_tracks_utm_params
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/landing?utm_source=google&utm_medium=cpc&utm_campaign=spring&utm_term=shoes&utm_content=ad1"))
    end

    payload = captured.first
    assert_equal "/landing", payload[:path]
    assert_equal "google", payload[:utm_source]
    assert_equal "cpc", payload[:utm_medium]
    assert_equal "spring", payload[:utm_campaign]
    assert_equal "shoes", payload[:utm_term]
    assert_equal "ad1", payload[:utm_content]
  end

  def test_omits_absent_and_blank_utm_params
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/landing?utm_source=google&utm_medium=&other=x"))
    end

    payload = captured.first
    assert_equal "google", payload[:utm_source]
    refute payload.key?(:utm_medium)
    refute payload.key?(:utm_campaign)
    refute payload.key?(:other)
  end

  def test_ignores_regex_path
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/assets/app.css"))
    end

    assert_empty captured
  end

  def test_ignores_string_path
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/up"))
    end

    assert_empty captured
  end

  def test_skips_non_get_requests
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "REQUEST_METHOD" => "POST"))
      middleware.call(env_for("/page", "REQUEST_METHOD" => "PUT"))
      middleware.call(env_for("/page", "REQUEST_METHOD" => "DELETE"))
    end

    assert_empty captured
  end

  def test_skips_xhr_requests
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest"))
    end

    assert_empty captured
  end

  def test_skips_non_html_responses
    middleware = WebtrackTracker::Middleware.new(JSON_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/api/users"))
    end

    assert_empty captured
  end

  def test_skips_non_2xx_responses
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      [301, 302, 404, 500].each do |code|
        app = ->(_env) { [code, { "Content-Type" => "text/html; charset=utf-8" }, ["<html>"]] }
        WebtrackTracker::Middleware.new(app).call(env_for("/page"))
      end
    end

    assert_empty captured
  end

  def test_tracks_html_response_with_charset
    middleware = WebtrackTracker::Middleware.new(HTML_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/about"))
    end

    assert_equal 1, captured.size
  end

  def test_skips_prefetch_requests
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "HTTP_SEC_PURPOSE" => "prefetch"))
      middleware.call(env_for("/page", "HTTP_PURPOSE"     => "prefetch"))
    end

    assert_empty captured
  end

  def test_skips_known_monitoring_bots
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    agents = [
      "Pingdom.com_bot_version_1.4_(http://www.pingdom.com/)",
      "UptimeRobot/2.0",
      "Datadog Agent/6.0",
      "NewRelicPinger/1.0"
    ]
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      agents.each { |ua| middleware.call(env_for("/page", "HTTP_USER_AGENT" => ua)) }
    end

    assert_empty captured
  end

  def test_sends_remote_addr_as_ip
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "REMOTE_ADDR" => "1.2.3.4"))
    end

    assert_equal "1.2.3.4", captured.first[:ip]
  end

  def test_prefers_x_forwarded_for_over_remote_addr
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page",
        "HTTP_X_FORWARDED_FOR" => "5.6.7.8, 10.0.0.1",
        "REMOTE_ADDR"          => "127.0.0.1"
      ))
    end

    assert_equal "5.6.7.8", captured.first[:ip]
  end

  def test_sends_user_agent_and_referrer
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page",
        "HTTP_USER_AGENT" => "TestBrowser/1.0",
        "HTTP_REFERER"    => "https://google.com"
      ))
    end

    assert_equal "TestBrowser/1.0",    captured.first[:user_agent]
    assert_equal "https://google.com", captured.first[:referrer]
  end

  def test_downcases_referrer
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "HTTP_REFERER" => "HTTPS://Google.COM/Search?Q=Foo"))
    end

    assert_equal "https://google.com/search?q=foo", captured.first[:referrer]
  end

  def test_sends_nil_referrer_when_absent
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page"))
    end

    assert_nil captured.first[:referrer]
  end

  def test_skips_dotfile_paths
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/.env"))
      middleware.call(env_for("/.pgpass"))
      middleware.call(env_for("/.git/config"))
    end

    assert_empty captured
  end

  def test_tracks_dot_inside_path
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/blog/.hidden-but-real"))
    end

    assert_equal 1, captured.size
  end

  def test_tracking_errors_do_not_affect_response
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    WebtrackTracker::Client.stub(:post_async, ->(*_) { raise "tracking boom" }) do
      status, = middleware.call(env_for("/page"))
      assert_equal 200, status
    end
  end

  def test_skips_tracking_in_disallowed_environment
    WebtrackTracker.configure { |c| c.environments = [:production] }
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    rails_stub = Module.new { def self.env = "development" }
    Object.const_set(:Rails, rails_stub)
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page"))
    end
    assert_empty captured
  ensure
    Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails) && Object.const_get(:Rails) == rails_stub
  end

  def test_app_errors_propagate_normally
    boom_app = ->(_env) { raise "app boom" }
    middleware = WebtrackTracker::Middleware.new(boom_app)
    assert_raises(RuntimeError, "app boom") do
      middleware.call(env_for("/"))
    end
  end

  def test_skips_ignored_ip
    WebtrackTracker.configure { |c| c.api_key = "test-key"; c.ignore_ips = ["1.2.3.4"] }
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "REMOTE_ADDR" => "1.2.3.4"))
    end
    assert_empty captured
  end

  def test_tracks_non_ignored_ip
    WebtrackTracker.configure { |c| c.api_key = "test-key"; c.ignore_ips = ["1.2.3.4"] }
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "REMOTE_ADDR" => "5.6.7.8"))
    end
    assert_equal 1, captured.size
  end

  def test_skips_ignored_ip_when_ipv4_mapped_ipv6
    WebtrackTracker.configure { |c| c.api_key = "test-key"; c.ignore_ips = ["1.2.3.4"] }
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "REMOTE_ADDR" => "::ffff:1.2.3.4"))
    end
    assert_empty captured
  end

  def test_skips_ignored_ip_cidr_range
    WebtrackTracker.configure { |c| c.api_key = "test-key"; c.ignore_ips = ["1.2.3.0/24"] }
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "REMOTE_ADDR" => "1.2.3.99"))
    end
    assert_empty captured
  end

  def test_tracks_ip_outside_ignored_cidr_range
    WebtrackTracker.configure { |c| c.api_key = "test-key"; c.ignore_ips = ["1.2.3.0/24"] }
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "REMOTE_ADDR" => "1.2.4.1"))
    end
    assert_equal 1, captured.size
  end

  def test_skips_request_with_ignored_ip_as_referrer_host
    WebtrackTracker.configure { |c| c.api_key = "test-key"; c.ignore_ips = ["1.2.3.4"] }
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "REMOTE_ADDR" => "9.9.9.9", "HTTP_REFERER" => "http://1.2.3.4/spam"))
    end
    assert_empty captured
  end

  def test_tracks_request_with_unignored_referrer
    WebtrackTracker.configure { |c| c.api_key = "test-key"; c.ignore_ips = ["1.2.3.4"] }
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "REMOTE_ADDR" => "9.9.9.9", "HTTP_REFERER" => "http://example.com/page"))
    end
    assert_equal 1, captured.size
  end

  def test_opt_out_route_sets_cookie
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    status, headers, = middleware.call(env_for("/webtrack/opt-out", "HTTP_REFERER" => "/page"))
    assert_equal 302, status
    assert_match "webtrack_exclude", headers["Set-Cookie"]
  end

  def test_opt_out_route_redirects_to_referer
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    _, headers, = middleware.call(env_for("/webtrack/opt-out", "HTTP_REFERER" => "/dashboard"))
    assert_equal "/dashboard", headers["Location"]
  end

  def test_opt_out_route_falls_back_to_root
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    _, headers, = middleware.call(env_for("/webtrack/opt-out"))
    assert_equal "/", headers["Location"]
  end

  def test_opt_out_return_to_takes_priority_over_referer
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    _, headers, = middleware.call(env_for(
      "/webtrack/opt-out?return_to=https://webtrack.info/sites/42/edit?opted_out=1",
      "HTTP_REFERER" => "/dashboard"
    ))
    assert_equal "https://webtrack.info/sites/42/edit?opted_out=1", headers["Location"]
  end

  def test_opt_out_return_to_external_absolute_url
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    _, headers, = middleware.call(env_for(
      "/webtrack/opt-out?return_to=https://webtrack.info/sites/42/edit"
    ))
    assert_equal "https://webtrack.info/sites/42/edit", headers["Location"]
  end

  def test_opt_in_return_to_external_absolute_url
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    _, headers, = middleware.call(env_for(
      "/webtrack/opt-in?return_to=https://webtrack.info/sites/42/edit"
    ))
    assert_equal "https://webtrack.info/sites/42/edit", headers["Location"]
  end

  def test_opt_in_route_clears_cookie
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    status, headers, = middleware.call(env_for("/webtrack/opt-in", "HTTP_REFERER" => "/page"))
    assert_equal 302, status
    assert_match "webtrack_exclude", headers["Set-Cookie"]
  end

  def test_opt_out_route_does_not_call_inner_app
    called = false
    inner_app = ->(_env) { called = true; [200, { "Content-Type" => "text/html" }, ["ok"]] }
    middleware = WebtrackTracker::Middleware.new(inner_app)
    middleware.call(env_for("/webtrack/opt-out"))
    refute called
  end

  def test_opt_out_cookie_suppresses_tracking
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "HTTP_COOKIE" => "webtrack_exclude=1"))
    end
    assert_empty captured
  end

  def test_custom_ignore_cookie_name
    WebtrackTracker.configure { |c| c.api_key = "test-key"; c.ignore_cookie = "my_opt_out" }
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "HTTP_COOKIE" => "my_opt_out=1"))
    end
    assert_empty captured
  end

  def test_nil_ignore_cookie_does_not_suppress_tracking
    WebtrackTracker.configure { |c| c.api_key = "test-key"; c.ignore_cookie = nil }
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    captured = []
    WebtrackTracker::Client.stub(:post_async, ->(_, payload) { captured << payload }) do
      middleware.call(env_for("/page", "HTTP_COOKIE" => "webtrack_exclude=1"))
    end
    assert_equal 1, captured.size
  end

  private

  def env_for(path, extras = {})
    Rack::MockRequest.env_for(path, { "HTTP_USER_AGENT" => "TestBrowser/1.0" }.merge(extras))
  end
end
