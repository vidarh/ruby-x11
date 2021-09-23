# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "X11/version"

Gem::Specification.new do |s| 
  s.name        = "ruby-x11"
  s.version     = X11::VERSION
  s.authors     = ["Richard Ramsden"]
  s.email       = ["richard@rramsden.ca"]
  s.homepage    = ""
  s.summary     = "Ruby X11 bindings"
  s.description = "Ruby X11 bindings"

  s.rubyforge_project = "ruby-x11"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
end
