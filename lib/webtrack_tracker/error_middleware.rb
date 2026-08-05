module WebtrackTracker
  # Catches the exceptions the Rails error reporter never sees.
  #
  # ActionDispatch::ShowExceptions only flags an exception for reporting when
  # it has no entry in ActionDispatch::ExceptionWrapper.rescue_responses:
  #
  #   request.set_header "action_dispatch.report_exception", !wrapper.rescue_response?
  #
  # Everything Rails turns into a status code by itself — RecordNotFound,
  # ParameterMissing, BadRequest, UnknownFormat, ParseError, invalid query
  # strings, … — is therefore invisible to Rails.error and thus to
  # ErrorSubscriber, while an APM agent with its own Rack middleware still
  # records it. That is the whole gap this middleware closes.
  #
  # It sits directly below DebugExceptions (see Railtie), where the exception
  # is still an exception, and reports exactly the complement: the
  # rescue_responses ones, nothing else. Errors that end in a 500 keep arriving
  # through the error reporter as before, so nothing is reported twice.
  #
  # Reported as handled with the source "webtrack_tracker.rack" — Rails did
  # render a response for these, so they stay distinguishable from real crashes
  # in Webtrack.
  class ErrorMiddleware
    SOURCE = "webtrack_tracker.rack"

    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue Exception => error
      report(error)
      raise
    end

    private

    def report(error)
      config = WebtrackTracker.config
      return unless config.errortracking
      return unless rescue_response?(error)

      reporter = error_reporter
      return unless reporter
      # Reporting goes through Rails.error and thus reaches every subscriber,
      # not just ours — so honour `environments` here too instead of letting
      # Client drop the payload at the very end.
      return unless config.environments.map(&:to_s).include?(current_env)

      reporter.report(error, handled: true, source: SOURCE)
    rescue StandardError
      nil # error tracking must never raise into the host app
    end

    # Mirrors ExceptionWrapper#rescue_response?, which also keys on the raised
    # class rather than on the unwrapped one.
    def rescue_response?(error)
      responses = rescue_responses
      return false unless responses

      responses.key?(error.class.name)
    end

    def rescue_responses
      ActionDispatch::ExceptionWrapper.rescue_responses if defined?(ActionDispatch::ExceptionWrapper)
    end

    def error_reporter
      Rails.error if defined?(Rails) && Rails.respond_to?(:error)
    end

    def current_env
      Rails.env.to_s
    end
  end
end
