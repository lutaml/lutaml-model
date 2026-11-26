# frozen_string_literal: true

# LML (subsumed language core) spec setup. Loaded alongside the gem-level
# spec_helper by the LML specs.

require "lutaml/lml"

RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{elk_layout_spec}) do |metadata|
    metadata[:skip] = "elkrb gem not available" unless (require "elkrb"; true) rescue false
  end
end

def fixtures_path(path)
  File.join(File.expand_path("fixtures", __dir__), path)
end

def by_name(entries, name)
  entries.detect { |n| n.name == name }
end
