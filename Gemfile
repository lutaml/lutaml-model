# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in lutaml-model.gemspec
gemspec

# Opal-compatible forks of oga and ruby-ll. The forks add pure-Ruby lexer
# and driver fallbacks (under ext/pureruby/) plus an Opal-aware conditional
# in lib/oga.rb / lib/ll/setup.rb that selects the pure-Ruby implementation
# when RUBY_PLATFORM == 'opal'. Under CRuby/JRuby the forks behave
# identically to upstream (the conditional falls through to liboga/libll).
gem "oga", path: "vendor/opal-oga"
gem "ruby-ll", path: "vendor/opal-ruby-ll"

# needed for liquid with ruby 3.4
gem "base64"
gem "benchmark-ips"
gem "bigdecimal"
gem "canon" # , path: "../canon"
gem "json-ld"
gem "liquid", "~> 5"
# lutaml-store depends on lutaml-model, so it can never be a gemspec dependency.
gem "lutaml-store", "~> 0.2"
gem "multi_json"
gem "nokogiri"
gem "oj"
gem "openssl", "~> 3.0"
gem "ox"
gem "rake"
gem "rdf-turtle"
gem "rexml"
# TODO: revert rng branch to main when lutaml/rng#32 is merged
gem "rng", git: "https://github.com/lutaml/rng", branch: "main"
gem "rspec"
gem "rubocop"
gem "rubocop-performance", require: false
gem "rubocop-rake", require: false
gem "rubocop-rspec", require: false
gem "tomlib"
gem "toml-rb"

# ruby-prof works on all platforms including Windows (unlike stackprof)
# Provides both CPU and memory profiling
gem "ruby-prof", group: :development

group :opal do
  gem "opal", "~> 1.8"
  gem "opal-rspec", "~> 1.0"
  gem "opal-sprockets"
end
