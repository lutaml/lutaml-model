# frozen_string_literal: true

# Invoked in a new Ruby process; never load the original mml library.
require_relative "../../../scripts/lml/export_mml"

package = ARGV.fetch(0)
raise "source Mml constants were already loaded" if Object.const_defined?(:Mml, false)

manifest = JSON.parse(File.read(File.join(package, "manifest.json")))
manifest.fetch("files").each do |entry|
  bytes = File.binread(File.join(package, entry.fetch("path")))
  unless LmlPreservation.digest(bytes) == entry.fetch("sha256")
    raise "payload digest mismatch: #{entry.fetch('path')}"
  end
end

oracles = JSON.parse(File.read(File.join(package, "oracle.json"))).fetch("cases")
results = oracles.each_with_index.map do |entry, index|
  id = entry.fetch("id")
  graph = manifest.fetch("graphs").fetch(id)
  # A refused closure is reported by name, never reconstructed from a pruned graph.
  next({ "id" => id, "refused" => graph.fetch("refusal") }) if graph.key?("refusal")

  bundle = Lutaml::Model::Lml::Importer.bundle(File.read(File.join(package, "#{id}.json")))
  raise "bundle checksum mismatch: #{id}" unless bundle.checksum == graph.fetch("checksum")

  derived = Lutaml::Model::Lml.verify_materialization(bundle)
  holder = Object.const_set("LmlMmlRebuilt#{index}", Module.new)
  classes = Lutaml::Model::Lml.import_bundle(bundle, namespace: holder)
  identities = classes.to_h { |model_id, klass| [klass, model_id] }
  { "id" => id, "model_count" => classes.size, "checksum" => derived.checksum,
    "actual" => LmlMml.replay(entry, classes.fetch(entry.fetch("model_id")), identities) }
end

raise "materialization loaded source Mml constants" if Object.const_defined?(:Mml, false)

File.write(ARGV.fetch(1), LmlPreservation.json("source_constants_loaded" => false, "cases" => results))
