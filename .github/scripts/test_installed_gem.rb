# frozen_string_literal: true

# Smoke test for the INSTALLED lutaml-model gem (parsanol-ruby
# pattern, lutaml-model#833): runs against the gem's own load paths —
# never the repo — and exercises the boot surface a packaging
# regression would break: every format round-trip and the Opal boot
# manifest's autoload coverage.

gem_root = Gem::Specification.find_by_name("lutaml-model").full_gem_path
raise "installed lutaml-model not found" unless gem_root

$LOAD_PATH.unshift(File.join(gem_root, "lib"))
require "lutaml/model"

# Boot manifest: every autoload in lib/compat/opal/lutaml_model_boot.rb
# must resolve from the installed gem alone.
boot = File.join(gem_root, "lib", "compat", "opal", "lutaml_model_boot.rb")
if File.exist?(boot)
  manifest = File.read(boot)
  missing = manifest.scan(/autoload[^\n]*["']([^"']+)["']/).flatten.select do |path|
    !File.exist?(File.join(gem_root, "lib", path))
  end
  raise "boot manifest references missing files: #{missing.inspect}" unless missing.empty?
end

class Smoke < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :count, :integer
  attribute :tags, :string, collection: true

  xml do
    root "smoke"
    map_attribute "name", to: :name
    map_element "count", to: :count
    map_element "tag", to: :tags
  end
end

require "tempfile"
model = Smoke.new(name: "smoke", count: 3, tags: %w[a b])

round_trips = {
  xml: -> { Smoke.from_xml(model.to_xml) },
  json: -> { Smoke.from_json(model.to_json) },
  yaml: -> { Smoke.from_yaml(model.to_yaml) },
  toml: -> { Smoke.from_toml(model.to_toml) },
  hash: -> { Smoke.from_hash(model.to_hash) },
}
round_trips.each do |format, parse|
  round = parse.call
  raise "#{format}: name lost" if round.name != "smoke"
  raise "#{format}: count lost" if round.count != 3
  raise "#{format}: tags lost" if Array(round.tags).sort != %w[a b]
end

puts "installed-gem smoke OK (#{gem_root}, " \
     "lutaml-model #{Lutaml::Model::VERSION}, " \
     "#{round_trips.keys.join("/")})"
