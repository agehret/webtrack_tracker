require "socket"

module WebtrackTracker
  # Subscriber for the Rails error reporter (Rails.error). Forwards every
  # reported exception to the Webtrack errors API — fire and forget via
  # Client.post_async, so the host app never waits for the tracker.
  #
  # Rails merges ActiveSupport::ExecutionContext into the reporter's context,
  # which carries the live controller instance for request errors and the job
  # instance for ActiveJob errors. Those objects are useless serialized as-is,
  # so they are unpacked into request data (controller#action, path, filtered
  # params, IP, user id, …) resp. job data and dropped from the payload.
  # Keys the host app sets itself (Rails.error.set_context) win over these.
  #
  # Enabled via config.errortracking (default: off); see Railtie.
  class ErrorSubscriber
    BACKTRACE_LIMIT = 200
    MESSAGE_LIMIT = 10_000

    def report(error, handled:, severity:, context: {}, source: nil)
      context = context.transform_keys(&:to_s)
      controller = context["controller"]
      job = context["job"]
      context.delete("controller") if live_controller?(controller)
      context.delete("job") if live_job?(job)

      merged = request_context(controller)
        .merge(job_context(job))
        .merge(context)

      payload = {
        exception_class: error.class.name,
        message: error.message.to_s[0, MESSAGE_LIMIT],
        backtrace: backtrace_for(error),
        environment: current_env,
        context: filtered_context(merged).merge(
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

    # The execution context can also hold plain values under these keys (e.g.
    # set_context(controller: "name")) — only unpack actual live instances.
    def live_controller?(controller)
      controller.respond_to?(:request) && controller.respond_to?(:action_name)
    end

    def live_job?(job)
      job.respond_to?(:job_id)
    end

    def request_context(controller)
      return {} unless live_controller?(controller)

      request = controller.request
      {
        "controller" => "#{controller.class.name}##{controller.action_name}",
        "method"     => request.request_method,
        "path"       => request.path,
        "params"     => request.filtered_parameters.except("controller", "action"),
        "ip"         => request.remote_ip,
        "user_agent" => request.user_agent,
        "referrer"   => request.referer,
        "request_id" => request.request_id,
        "user_id"    => user_id_from(controller)
      }.compact
    rescue StandardError
      {}
    end

    # Best effort: works with Devise and most hand-rolled auth. Apps with a
    # different scheme can report their own via Rails.error.set_context.
    def user_id_from(controller)
      return nil unless controller.respond_to?(:current_user, true)

      user = controller.send(:current_user)
      user.respond_to?(:id) ? user.id : nil
    rescue StandardError
      nil
    end

    def job_context(job)
      return {} unless live_job?(job)

      {
        "job"        => job.class.name,
        "job_id"     => job.job_id,
        "queue"      => (job.queue_name if job.respond_to?(:queue_name)),
        "executions" => (job.executions if job.respond_to?(:executions)),
        "arguments"  => job_arguments(job)
      }.compact
    rescue StandardError
      {}
    end

    # The serialized form, not job.arguments: models stay compact GlobalID
    # URIs (gid://…) instead of dumping their attributes, and keyword args
    # remain hashes so filter_parameters can still mask them.
    def job_arguments(job)
      job.serialize["arguments"] if job.respond_to?(:serialize)
    rescue StandardError
      nil
    end

    # Runs the backtrace through the host app's Rails.backtrace_cleaner, which
    # by default silences framework frames and makes app frames relative — the
    # same concise trace Rails shows on its error pages. An error raised wholly
    # inside framework code silences to nothing; in that case we keep all frames
    # (still cleaned) rather than send an empty backtrace, and fall back to the
    # raw trace when no cleaner is available.
    def backtrace_for(error)
      raw = Array(error.backtrace).first(BACKTRACE_LIMIT)
      cleaner = backtrace_cleaner
      return raw unless cleaner

      cleaned = presence(cleaner.clean(raw)) || presence(cleaner.clean(raw, :all))
      cleaned || raw
    rescue StandardError
      Array(error.backtrace).first(BACKTRACE_LIMIT)
    end

    def presence(array)
      array if array && !array.empty?
    end

    def backtrace_cleaner
      Rails.backtrace_cleaner if defined?(Rails) && Rails.respond_to?(:backtrace_cleaner)
    end

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
