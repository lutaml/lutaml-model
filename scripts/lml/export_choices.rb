# frozen_string_literal: true

# ruby -Ilib scripts/lml/export_choices.rb OUTPUT [Plain Nested ...]
# Omitting names exports every source fixture, including eager field failures.
require "json"
require "digest"
require_relative "../../spec/support/lml_model_choices_fixtures"

Lutaml::Model::Config.xml_adapter_type = :nokogiri
output = ARGV.shift || abort("usage: export_choices.rb OUTPUT [fixture names]")
selected = ARGV.empty? ? LmlModelChoicesFixtures::CASES.keys : ARGV
sources = selected.to_h do |name|
  [name, LmlModelChoicesFixtures.const_get(name, false)]
end
codes = lambda do |value|
  value.validate.map do |error|
    case error
    when Lutaml::Model::ChoiceLowerBoundError then "choice_lower_bound"
    when Lutaml::Model::ChoiceUpperBoundError then "choice_upper_bound"
    else error.class.name
    end
  end
end
phase = lambda do |&block|
  codes.call(block.call)
rescue Lutaml::Model::CollectionCountOutOfRangeError
  ["eager_collection_count_out_of_range"]
end
rows = sources.flat_map do |name, klass|
  LmlModelChoicesFixtures::CASES.fetch(name).each_with_index.map do |input, index|
    value = klass.new(input)
    json = value.to_json
    xml = value.to_xml
    {
      id: "#{name}-#{index}", model_id: "#{klass.name}@default", input: input,
      expected: {
        construct: codes.call(value),
        json_input: phase.call { klass.from_json(JSON.generate(input)) },
        json_wire: JSON.parse(json),
        json_roundtrip: phase.call { klass.from_json(json) },
        xml_wire: xml,
        xml_roundtrip: phase.call { klass.from_xml(xml) },
      }
    }
  end
end
root = File.expand_path("../..", __dir__)
producer_files = %w[lib/lutaml/model/choice.rb lib/lutaml/model/validation.rb
                    spec/support/lml_model_choices_fixtures.rb]
producer = producer_files.to_h { |file| [file, Digest::SHA256.file(File.join(root, file)).hexdigest] }
report = {
  source_semantics: "native Choice/Validation and format-specific I/O; group validation unchanged",
  ruby: RUBY_VERSION, producer: producer,
  bundle: Lutaml::Model::Lml.export_bundle(sources.values).to_h, cases: rows
}
File.write(output, "#{JSON.pretty_generate(report)}\n")
puts JSON.generate(models: report[:bundle].fetch("models").length, cases: rows.length)
