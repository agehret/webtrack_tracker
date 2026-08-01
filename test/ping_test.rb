require "test_helper"

class PingTest < Minitest::Test
  def setup
    super
    WebtrackTracker.configure do |c|
      c.endpoint     = "https://localhost"
      c.timeout      = 2
      c.environments = [ENV["RACK_ENV"] || "development"]
      c.checkins     = { backup: "backup-token-123" }
    end
  end

  def http_stub(&request_handler)
    stub = Object.new
    def stub.use_ssl=(_); end
    def stub.open_timeout=(_); end
    def stub.read_timeout=(_); end
    stub.define_singleton_method(:request, &request_handler)
    stub
  end

  def ok_response
    Net::HTTPOK.new("1.1", "200", "OK")
  end

  def test_ping_resolves_configured_checkin_and_returns_true
    requested_path = nil
    response = ok_response
    stub = http_stub do |req|
      requested_path = req.path
      response
    end

    Net::HTTP.stub(:new, stub) do
      assert_equal true, WebtrackTracker.ping(:backup)
    end

    assert_equal "/ping/backup-token-123", requested_path
  end

  def test_ping_accepts_string_name_for_symbol_config
    response = ok_response
    stub = http_stub { |_req| response }

    Net::HTTP.stub(:new, stub) do
      assert_equal true, WebtrackTracker.ping("backup")
    end
  end

  def test_ping_accepts_raw_token
    requested_path = nil
    response = ok_response
    stub = http_stub do |req|
      requested_path = req.path
      response
    end

    Net::HTTP.stub(:new, stub) do
      assert_equal true, WebtrackTracker.ping(token: "raw-token-9")
    end

    assert_equal "/ping/raw-token-9", requested_path
  end

  def test_ping_returns_false_and_logs_for_unknown_checkin
    log_output = StringIO.new
    WebtrackTracker::Client.instance_variable_set(:@logger, Logger.new(log_output))

    assert_equal false, WebtrackTracker.ping(:unbekannt)
    assert_match "no token for check-in :unbekannt", log_output.string
  ensure
    WebtrackTracker::Client.instance_variable_set(:@logger, nil)
  end

  def test_ping_returns_false_when_environment_not_tracked
    WebtrackTracker.config.environments = [:production]

    requests = 0
    response = ok_response
    stub = http_stub do |_req|
      requests += 1
      response
    end

    Net::HTTP.stub(:new, stub) do
      assert_equal false, WebtrackTracker.ping(:backup)
    end

    assert_equal 0, requests
  end

  def test_ping_requires_https_endpoint
    WebtrackTracker.config.endpoint = "http://localhost"

    assert_equal false, WebtrackTracker.ping(:backup)
  end

  def test_ping_does_not_retry_client_errors
    requests = 0
    stub = http_stub do |_req|
      requests += 1
      Net::HTTPNotFound.new("1.1", "404", "Not Found")
    end

    Net::HTTP.stub(:new, stub) do
      assert_equal false, WebtrackTracker.ping(:backup)
    end

    assert_equal 1, requests
  end

  def test_ping_retries_network_errors_then_succeeds
    requests = 0
    response = ok_response
    stub = http_stub do |_req|
      requests += 1
      raise Errno::ECONNREFUSED if requests == 1
      response
    end

    Net::HTTP.stub(:new, stub) do
      assert_equal true, WebtrackTracker.ping(:backup)
    end

    assert_equal 2, requests
  end

  def test_ping_gives_up_after_all_attempts
    requests = 0
    stub = http_stub do |_req|
      requests += 1
      raise Errno::ECONNREFUSED
    end

    Net::HTTP.stub(:new, stub) do
      assert_equal false, WebtrackTracker.ping(:backup)
    end

    assert_equal WebtrackTracker::Client::PING_ATTEMPTS, requests
  end
end
