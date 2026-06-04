require "minitest/autorun"
require "rack/mock"
require "webtrack_tracker"

module Minitest
  class Test
    def setup
      WebtrackTracker.instance_variable_set(:@config, nil)
    end
  end
end
