module WebtrackTracker
  class Configuration
    attr_accessor :api_key, :endpoint, :environments, :ignore_paths, :ignore_ips, :timeout, :debug_mode

    def initialize
      @endpoint     = "https://webtrack.example.com"
      @environments = [:production]
      @ignore_paths = []
      @ignore_ips   = []
      @timeout      = 5
      @debug_mode   = false
    end
  end
end
