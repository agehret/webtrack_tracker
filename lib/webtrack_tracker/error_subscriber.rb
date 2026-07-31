require "socket"

module WebtrackTracker
  # Subscriber for the Rails error reporter (Rails.error). Forwards every
  # reported exception to the Webtrack errors API — fire and forget via
  # Client.post_async, so the host app never waits for the tracker.
  #
  # Enabled via config.errortracking (default: off); see Railtie.
  class ErrorSubscriber
    BACKTRACE_LIMIT = 200
    MESSAGE_LIMIT = 10_000

    def report(error, handled:, severity:, context: {}, source: nil)
      payload = {
        exception_class: error.class.name,
        message: error.message.to_s[0, MESSAGE_LIMIT],
        backtrace: Array(error.backtrace).first(BACKTRACE_LIMIT),
        environment: current_env,
        context: filtered_context(context).merge(
          "hostname" => hostname,
          "handled"  => handled,
          "severity" => severity.to_s,
          "source"   => source
        ).compact
      }

      Client.post_async("/api/errors", payload)
    rescue StandardError
      nil # error tracking must never raise into the host app
    end

    private

    # Masks params and friends with the host app's filter rules
    # (Rails.application.config.filter_parameters).
    def filtered_context(context)
      context = context.transform_keys(&:to_s)
      return context unless defined?(Rails) && defined?(ActiveSupport::ParameterFilter) && Rails.application

      ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(context)
    rescue StandardError
      {}
    end

    def current_env
      if defined?(Rails)
        Rails.env.to_s
      else
        ENV["RACK_ENV"] || ENV["APP_ENV"] || "development"
      end
    end

    def hostname
      Socket.gethostname
    rescue StandardError
      nil
    end
  end
end
