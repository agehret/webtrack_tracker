require "net/http"
require "uri"
require "json"
require "concurrent"

module WebtrackTracker
  class Client
    def self.post_async(api_path, payload)
      config = WebtrackTracker.config
      return unless config.api_key

      Concurrent::Future.execute(executor: :io) do
        post(config.endpoint, config.api_key, config.timeout, api_path, payload)
      end
    rescue StandardError
      nil
    end

    private_class_method def self.post(base_url, api_key, timeout, api_path, payload)
      uri = URI.parse("#{base_url.to_s.chomp('/')}#{api_path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = timeout
      http.read_timeout = timeout

      request = Net::HTTP::Post.new(uri.path)
      request["X-Api-Key"] = api_key
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)

      http.request(request)
    rescue StandardError
      nil
    end
  end
end
