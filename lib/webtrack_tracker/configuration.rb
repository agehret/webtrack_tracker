module WebtrackTracker
  class Configuration
    attr_accessor :api_key, :endpoint, :ignore_paths, :timeout

    def initialize
      @endpoint = "https://webtrack.example.com"
      @ignore_paths = []
      @timeout = 5
    end
  end
end
