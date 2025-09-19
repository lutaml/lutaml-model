# frozen_string_literal: true

require "json"
require "benchmark"
# Ensure lib/ is on the load path regardless of tmp location
$LOAD_PATH.unshift(File.expand_path(File.join(__dir__, "..", "..", "lib")))
require "lutaml/model"
require "lutaml/model/xml/nokogiri_adapter"
require "lutaml/model/xml/ox_adapter"
require "lutaml/model/xml/oga_adapter"
require "lutaml/model/json/standard_adapter"
require "lutaml/model/json/multi_json_adapter"
require "lutaml/model/json/oj_adapter"
require "lutaml/model/yaml/standard_adapter"
require "lutaml/model/toml/toml_rb_adapter"
require "lutaml/model/toml/tomlib_adapter"

runs = Integer(ENV.fetch("RUNS", 10))
items = Integer(ENV.fetch("ITEMS", 1000))
filter_format = ENV["FILTER_FORMAT"]&.to_sym
filter_adapter = ENV["FILTER_ADAPTER"]&.to_sym

def generate_xml(items)
  "<root>#{(0...items).map { |i| "<item id='#{i}'><name>Test #{i}</name><value>#{i}</value></item>" }.join}</root>"
end

def generate_json(items)
  {
    "item" => (0...items).map { |i| { "id" => i, "name" => "Test #{i}", "value" => i } },
  }.to_json
end

def generate_yaml(items)
  [
    "item:",
    (0...items).map { |i| "  - id: #{i}\n    name: 'Test #{i}'\n    value: #{i}" },
  ].flatten.join("\n")
end

def generate_toml(items)
  (0...items).flat_map do |i|
    [
      "[[item]]",
      "id = #{i}",
      "name = \"Test #{i}\"",
      "value = #{i}",
      "",
    ]
  end.join("\n")
end

class BenchItem < Lutaml::Model::Serializable
  attribute :id, :integer
  attribute :name, :string
  attribute :value, :integer

  xml do
    map_attribute "id", to: :id
    map_element "value", to: :value
    map_element "name", to: :name
  end

  json do
    map "id", to: :id
    map "name", to: :name
    map "value", to: :value
  end

  yaml do
    map "id", to: :id
    map "name", to: :name
    map "value", to: :value
  end

  toml do
    map "id", to: :id
    map "name", to: :name
    map "value", to: :value
  end
end

class BenchRoot < Lutaml::Model::Serializable
  attribute :item, BenchItem, collection: true

  xml do
    root "root"
    map_element "item", to: :item
  end

  json do
    map "item", to: :item
  end

  yaml do
    map "item", to: :item
  end

  toml do
    map "item", to: :item
  end
end

def time_runs(runs, &block)
  t = Benchmark.realtime do
    runs.times(&block)
  end

  { ips: runs / t }
end

def set_adapter(format, adapter)
  Lutaml::Model::Config.send("#{format}_adapter_type=", adapter)
end

def parsed_count(format, input)
  BenchRoot.send("from_#{format}", input).item.size
end

def run_benchmark(format, adapter, input, runs, expected_count)
  set_adapter(format, adapter)
  res = time_runs(runs) { BenchRoot.send("from_#{format}", input) }
  res[:label] = "#{format}_parse_#{adapter}"
  res[:correct] = parsed_count(format, input) == expected_count
  res
end

def run_benchmarks_for(format, adapters, input, runs, expected_count, results, model)
  adapters.each do |adapter|
    result = run_benchmark(format, adapter, input, runs, expected_count)
    results[result[:label]] = result

    result = run_serialize_benchmark(format, adapter, model, runs, expected_count)
    results[result[:label]] = result
  end
end

def build_model(items)
  root = BenchRoot.new
  root.item = (0...items).map do |i|
    BenchItem.new(id: i, name: "Test #{i}", value: i)
  end
  root
end

def run_serialize_benchmark(format, adapter, model, runs, expected_count)
  set_adapter(format, adapter)
  res = time_runs(runs) { model.send("to_#{format}") }
  res[:label] = "#{format}_serialize_#{adapter}"
  serialized = model.send("to_#{format}")
  res[:correct] = parsed_count(format, serialized) == expected_count
  res
end

results = {}

# Generate inputs once
xml_input = generate_xml(items)
json_input = generate_json(items)
yaml_input = generate_yaml(items)
toml_input = generate_toml(items)

model = build_model(items)
def maybe_run(format_sym, adapters, input, runs, items, results, model, filter_format, filter_adapter)
  return if filter_format && filter_format != format_sym

  selected = filter_adapter ? adapters.select { |a| a == filter_adapter } : adapters
  return if selected.empty?

  run_benchmarks_for(format_sym, selected, input, runs, items, results, model)
end

# Run XML
maybe_run(:xml, %i[nokogiri ox oga], xml_input, runs, items, results, model, filter_format, filter_adapter)

# Run JSON
maybe_run(:json, %i[standard_json multi_json oj], json_input, runs, items, results, model, filter_format, filter_adapter)

# Run YAML
maybe_run(:yaml, %i[standard_yaml], yaml_input, runs, items, results, model, filter_format, filter_adapter)

# Run TOML
maybe_run(:toml, %i[toml_rb tomlib], toml_input, runs, items, results, model, filter_format, filter_adapter)

puts JSON.dump(results)
