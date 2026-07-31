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

  def test_backtrace_uses_the_silenced_app_only_cleaner_output
    fake = FakeCleaner.new(silence: [ "app/models/user.rb:42:in 'find_name'" ])

    calls = capture_post do
      subscriber.stub(:backtrace_cleaner, fake) do
        subscriber.report(sample_error, handled: false, severity: :error, context: {})
      end
    end

    _path, payload = calls.first
    assert_equal [ :silence ], fake.kinds, "must prefer the default (silencing) cleaner, app-only"
    assert_equal [ "app/models/user.rb:42:in 'find_name'" ], payload[:backtrace]
  end

  def test_backtrace_falls_back_to_all_frames_for_framework_only_errors
    fake = FakeCleaner.new(silence: [], all: [ "actionpack (8.1.3) lib/x.rb:1:in 'call'" ])

    calls = capture_post do
      subscriber.stub(:backtrace_cleaner, fake) do
        subscriber.report(sample_error, handled: false, severity: :error, context: {})
      end
    end

    _path, payload = calls.first
    assert_equal [ :silence, :all ], fake.kinds, "empty app-only trace should fall back to all frames"
    assert_equal [ "actionpack (8.1.3) lib/x.rb:1:in 'call'" ], payload[:backtrace]
  end

  def test_backtrace_falls_back_to_raw_when_the_cleaner_returns_nothing
    calls = capture_post do
      subscriber.stub(:backtrace_cleaner, FakeCleaner.new(silence: [], all: [])) do
        subscriber.report(sample_error, handled: false, severity: :error, context: {})
      end
    end

    _path, payload = calls.first
    assert payload[:backtrace].any?, "an empty cleaner result must not blank out the backtrace"
  end

  def test_errortracking_config_defaults_to_off
    refute WebtrackTracker.config.errortracking
  end

  def test_request_context_is_unpacked_from_the_controller
    calls = capture_post do
      subscriber.report(sample_error, handled: false, severity: :error, context: { controller: FakeController.new })
    end

    _path, payload = calls.first
    ctx = payload[:context]
    assert_equal "ErrorSubscriberTest::FakeController#show", ctx["controller"]
    assert_equal "GET", ctx["method"]
    assert_equal "/posts/1", ctx["path"]
    assert_equal({ "id" => "1", "password" => "[FILTERED]" }, ctx["params"])
    assert_equal "203.0.113.9", ctx["ip"]
    assert_equal "TestBrowser/1.0", ctx["user_agent"]
    assert_equal "https://example.com/", ctx["referrer"]
    assert_equal "req-abc-123", ctx["request_id"]
    assert_equal 7, ctx["user_id"]
  end

  def test_host_app_context_wins_over_extracted_request_context
    calls = capture_post do
      subscriber.report(sample_error, handled: false, severity: :error,
        context: { controller: FakeController.new, user_id: 99 })
    end

    _path, payload = calls.first
    assert_equal 99, payload[:context]["user_id"]
  end

  def test_a_plain_controller_context_value_is_left_alone
    calls = capture_post do
      subscriber.report(sample_error, handled: false, severity: :error, context: { controller: "manual" })
    end

    _path, payload = calls.first
    assert_equal "manual", payload[:context]["controller"]
  end

  def test_controllers_without_current_user_report_no_user_id
    calls = capture_post do
      subscriber.report(sample_error, handled: false, severity: :error, context: { controller: FakeControllerWithoutUser.new })
    end

    _path, payload = calls.first
    refute payload[:context].key?("user_id")
    assert_equal "/posts/1", payload[:context]["path"]
  end

  def test_job_context_is_unpacked_from_the_job
    calls = capture_post do
      subscriber.report(sample_error, handled: false, severity: :error, context: { job: FakeJob.new })
    end

    _path, payload = calls.first
    ctx = payload[:context]
    assert_equal "ErrorSubscriberTest::FakeJob", ctx["job"]
    assert_equal "job-uuid-1", ctx["job_id"]
    assert_equal "mailers", ctx["queue"]
    assert_equal 3, ctx["executions"]
    assert_equal [ "gid://app/User/1" ], ctx["arguments"]
  end

  class FakeRequest
    def request_method = "GET"
    def path = "/posts/1"
    def filtered_parameters = { "controller" => "posts", "action" => "show", "id" => "1", "password" => "[FILTERED]" }
    def remote_ip = "203.0.113.9"
    def user_agent = "TestBrowser/1.0"
    def referer = "https://example.com/"
    def request_id = "req-abc-123"
  end

  class FakeController
    def request = FakeRequest.new
    def action_name = "show"

    private

    def current_user = Struct.new(:id).new(7)
  end

  class FakeControllerWithoutUser
    def request = FakeRequest.new
    def action_name = "show"
  end

  class FakeJob
    def job_id = "job-uuid-1"
    def queue_name = "mailers"
    def executions = 3
    def serialize = { "job_class" => "FakeJob", "arguments" => [ "gid://app/User/1" ] }
  end

  # Mirrors Rails.backtrace_cleaner#clean(backtrace, kind = :silence): the
  # default silences framework frames, any other kind (:all) keeps them.
  class FakeCleaner
    attr_reader :kinds

    def initialize(silence:, all: silence)
      @results = { silence: silence, all: all }
      @kinds = []
    end

    def clean(_backtrace, kind = :silence)
      @kinds << kind
      @results.fetch(kind, [])
    end
  end
end
