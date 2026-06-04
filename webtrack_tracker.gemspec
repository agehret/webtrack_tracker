require_relative "lib/webtrack_tracker/version"

Gem::Specification.new do |spec|
  spec.name     = "webtrack_tracker"
  spec.version  = WebtrackTracker::VERSION
  spec.authors  = ["Andreas Gehret"]
  spec.email    = ["andreas@gehret.de"]
  spec.summary  = "Rack middleware for non-blocking page-view tracking via Webtrack"
  spec.homepage = "https://github.com/agehret/webtrack_tracker"
  spec.license  = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files         = Dir["lib/**/*.rb", "*.gemspec"]
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", "~> 1.0"
  spec.add_dependency "logger", ">= 1.4"
  spec.add_dependency "rack", ">= 2.0"
end
