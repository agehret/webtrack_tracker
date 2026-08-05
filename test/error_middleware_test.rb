require "test_helper"
require "minitest/mock"

class ErrorMiddlewareTest < Minitest::Test
  # Stands in for ActiveRecord::RecordNotFound & friends: Rails maps these to a
  # status code itself and therefore never hands them to Rails.error.
  class NotFound < StandardError; end
  # Stands in for a plain 500 — the error reporter already sees this one.
  class Boom < StandardError; end

  RESCUE_RESPONSES = { NotFound.name => :not_found }.freeze

  OK_APP    = ->(_env) { [ 200, { "Content-Type" => "text/html" }, [ "<html>" ] ] }
  BOOM_APP  = ->(_env) { raise Boom, "kaputt" }
  NOT_FOUND = ->(_env) { raise NotFound, "no such record" }

  def setup
    super
    WebtrackTracker.configure do |c|
      c.api_key      = "test-key"
      c.errortracking = true
      c.environments  = [ :production ]
    end
  end

  # Records what the middleware hands to Rails.error.
  class FakeReporter
    attr_reader :calls

    def initialize = @calls = []

    def report(error, handled:, source: nil)
      @calls << { error: error, handled: handled, source: source }
    end
  end

  def middleware_for(app, reporter: FakeReporter.new, env: "production", responses: RESCUE_RESPONSES)
    middleware = WebtrackTracker::ErrorMiddleware.new(app)
    middleware.stub(:error_reporter, reporter) do
      middleware.stub(:current_env, env) do
        middleware.stub(:rescue_responses, responses) do
          yield middleware, reporter
        end
      end
    end
  end

  def test_passes_through_app_response
    middleware_for(OK_APP) do |middleware, reporter|
      status, _headers, body = middleware.call({})
      assert_equal 200, status
      assert_equal [ "<html>" ], body
      assert_empty reporter.calls
    end
  end

  def test_reports_exceptions_rails_maps_to_a_status_code
    middleware_for(NOT_FOUND) do |middleware, reporter|
      assert_raises(NotFound) { middleware.call({}) }

      assert_equal 1, reporter.calls.size
      call = reporter.calls.first
      assert_instance_of NotFound, call[:error]
      assert_equal true, call[:handled]
      assert_equal "webtrack_tracker.rack", call[:source]
    end
  end

  def test_ignores_exceptions_the_error_reporter_already_sees
    middleware_for(BOOM_APP) do |middleware, reporter|
      assert_raises(Boom) { middleware.call({}) }
      assert_empty reporter.calls, "a plain 500 is reported by ActionDispatch::Executor — would be a duplicate"
    end
  end

  def test_does_nothing_when_errortracking_is_off
    WebtrackTracker.config.errortracking = false

    middleware_for(NOT_FOUND) do |middleware, reporter|
      assert_raises(NotFound) { middleware.call({}) }
      assert_empty reporter.calls
    end
  end

  def test_does_nothing_outside_the_tracked_environments
    middleware_for(NOT_FOUND, env: "development") do |middleware, reporter|
      assert_raises(NotFound) { middleware.call({}) }
      assert_empty reporter.calls
    end
  end

  def test_does_nothing_without_action_dispatch
    middleware_for(NOT_FOUND, responses: nil) do |middleware, reporter|
      assert_raises(NotFound) { middleware.call({}) }
      assert_empty reporter.calls
    end
  end

  def test_reraises_the_original_exception_when_reporting_blows_up
    exploding = Object.new
    def exploding.report(*) = raise("reporter down")

    middleware_for(NOT_FOUND, reporter: exploding) do |middleware, _reporter|
      error = assert_raises(NotFound) { middleware.call({}) }
      assert_equal "no such record", error.message
    end
  end

  def test_reraises_exceptions_that_are_not_standard_errors
    middleware_for(->(_env) { raise NotImplementedError, "nope" }) do |middleware, reporter|
      assert_raises(NotImplementedError) { middleware.call({}) }
      assert_empty reporter.calls
    end
  end
end
