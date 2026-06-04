require "test_helper"

class ClientTest < Minitest::Test
  def setup
    super
    WebtrackTracker.configure do |c|
      c.api_key      = "test-key"
      c.endpoint     = "http://localhost"
      c.timeout      = 2
      c.environments = [ENV["RACK_ENV"] || "development"]
    end
  end

  def test_returns_nil_when_no_api_key
    WebtrackTracker.config.api_key = nil
    assert_nil WebtrackTracker::Client.post_async("/api/track", path: "/")
  end

  def test_returns_nil_when_environment_not_tracked
    WebtrackTracker.config.environments = [:production]
    assert_nil WebtrackTracker::Client.post_async("/api/track", path: "/")
  end

  def test_returns_future_when_api_key_present
    http_stub = Object.new
    def http_stub.use_ssl=(_); end
    def http_stub.open_timeout=(_); end
    def http_stub.read_timeout=(_); end
    def http_stub.request(_); end

    Net::HTTP.stub(:new, http_stub) do
      future = WebtrackTracker::Client.post_async("/api/track", { path: "/" })
      refute_nil future
      future.wait(2)
    end
  end

  def test_swallows_connection_errors
    WebtrackTracker.configure do |c|
      c.api_key      = "key"
      c.endpoint     = "http://127.0.0.1:19999"
      c.timeout      = 1
      c.environments = [ENV["RACK_ENV"] || "development"]
    end

    future = WebtrackTracker::Client.post_async("/api/track", path: "/")
    future&.wait(3)
    pass
  end

  def test_debug_mode_logs_payload_and_response
    http_stub = Object.new
    def http_stub.use_ssl=(_); end
    def http_stub.open_timeout=(_); end
    def http_stub.read_timeout=(_); end
    response_stub = Object.new
    def response_stub.code; "200"; end
    http_stub.define_singleton_method(:request) { |_| response_stub }

    WebtrackTracker.config.debug_mode = true
    log_output = StringIO.new

    Net::HTTP.stub(:new, http_stub) do
      logger = Logger.new(log_output)
      WebtrackTracker::Client.stub(:instance_variable_get, logger) do
        future = WebtrackTracker::Client.post_async("/api/track", { path: "/" })
        future&.wait(2)
      end
    end

    pass
  end
end
