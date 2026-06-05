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

  private

  def env_for(path, extras = {})
    Rack::MockRequest.env_for(path, { "HTTP_USER_AGENT" => "TestBrowser/1.0" }.merge(extras))
  end
end
