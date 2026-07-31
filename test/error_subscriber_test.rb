require "test_helper"
require "minitest/mock"

class ErrorSubscriberTest < Minitest::Test
  def subscriber
    @subscriber ||= WebtrackTracker::ErrorSubscriber.new
  end

  def sample_error
    raise ArgumentError, "boom"
  rescue ArgumentError => e
    e
  end

  def capture_post(&block)
    calls = []
    WebtrackTracker::Client.stub(:post_async, ->(path, payload) { calls << [ path, payload ] }, &block)
    calls
  end

  def test_report_posts_error_payload
    calls = capture_post do
      subscriber.report(sample_error, handled: false, severity: :error, context: { user_id: 7 }, source: "application")
    end

    path, payload = calls.first
    assert_equal "/api/errors", path
    assert_equal "ArgumentError", payload[:exception_class]
    assert_equal "boom", payload[:message]
    assert payload[:backtrace].any?
    assert_equal 7, payload[:context]["user_id"]
    assert_equal false, payload[:context]["handled"]
    assert_equal "error", payload[:context]["severity"]
    assert_equal "application", payload[:context]["source"]
    assert payload[:context]["hostname"]
  end

  def test_report_omits_source_when_absent
    calls = capture_post do
      subscriber.report(sample_error, handled: true, severity: :warning, context: {})
    end

    _path, payload = calls.first
    refute payload[:context].key?("source")
    assert_equal true, payload[:context]["handled"]
  end

  def test_report_never_raises
    broken = Object.new # responds to nothing the subscriber needs

    capture_post do
      assert_nil subscriber.report(broken, handled: true, severity: :warning, context: {})
    end
  end

  def test_errortracking_config_defaults_to_off
    refute WebtrackTracker.config.errortracking
  end
end
