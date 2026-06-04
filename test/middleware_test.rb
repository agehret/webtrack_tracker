require "test_helper"

class MiddlewareTest < Minitest::Test
  DUMMY_APP = ->(_env) { [200, { "Content-Type" => "text/plain" }, ["OK"]] }

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
      assert_equal ["OK"], body
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

    assert_equal "TestBrowser/1.0",   captured.first[:user_agent]
    assert_equal "https://google.com", captured.first[:referrer]
  end

  def test_tracking_errors_do_not_affect_response
    middleware = WebtrackTracker::Middleware.new(DUMMY_APP)
    WebtrackTracker::Client.stub(:post_async, ->(*_) { raise "tracking boom" }) do
      status, = middleware.call(env_for("/page"))
      assert_equal 200, status
    end
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
    Rack::MockRequest.env_for(path, extras)
  end
end
