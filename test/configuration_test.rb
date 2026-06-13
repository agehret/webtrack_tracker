require "test_helper"

class ConfigurationTest < Minitest::Test
  def test_defaults
    config = WebtrackTracker::Configuration.new
    assert_equal "https://webtrack.example.com", config.endpoint
    assert_equal [:production], config.environments
    assert_equal [], config.ignore_paths
    assert_equal [], config.ignore_ips
    assert_equal "webtrack_exclude", config.ignore_cookie
    assert_equal 5, config.timeout
    assert_nil config.api_key
    refute config.debug_mode
  end

  def test_configure_block_sets_values
    WebtrackTracker.configure do |c|
      c.api_key  = "test-key"
      c.endpoint = "https://custom.example.com"
      c.timeout  = 3
    end

    assert_equal "test-key",                WebtrackTracker.config.api_key
    assert_equal "https://custom.example.com", WebtrackTracker.config.endpoint
    assert_equal 3,                          WebtrackTracker.config.timeout
  end

  def test_ignore_paths_accepts_mixed_patterns
    WebtrackTracker.configure do |c|
      c.ignore_paths = [%r{\A/assets/}, "/up"]
    end

    assert_equal 2, WebtrackTracker.config.ignore_paths.length
    assert_kind_of Regexp, WebtrackTracker.config.ignore_paths.first
    assert_kind_of String, WebtrackTracker.config.ignore_paths.last
  end

  def test_config_is_memoized
    assert_same WebtrackTracker.config, WebtrackTracker.config
  end
end
