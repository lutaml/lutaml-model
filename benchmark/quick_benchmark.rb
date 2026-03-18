# frozen_string_literal: true

# Lutaml::Model Quick Benchmark
#
# A lightweight benchmark that runs without additional dependencies.
# Uses only Ruby's built-in Benchmark module.
#
# Usage:
#   bundle exec ruby benchmark/quick_benchmark.rb
#

require "bundler/setup"
require "lutaml/model"
require "benchmark"
require "json"

# Configure adapters
Lutaml::Model.configure do |config|
  config.xml_adapter = :nokogiri
  config.json_adapter = :standard
end

# ============================================================================
# Test Models
# ============================================================================

class Item < Lutaml::Model::Serializable
  attribute :id, :integer
  attribute :name, :string
  attribute :value, :float

  xml do
    root "item"
    map_attribute "id", to: :id
    map_element "name", to: :name
    map_element "value", to: :value
  end

  json do
    map "id", to: :id
    map "name", to: :name
    map "value", to: :value
  end
end

class Container < Lutaml::Model::Serializable
  attribute :items, Item, collection: true

  xml do
    root "container"
    map_element "item", to: :items
  end

  json do
    map "items", to: :items
  end
end

# ============================================================================
# Benchmark Configuration
# ============================================================================

ITERATIONS = 1000
WARMUP = 100

# ============================================================================
# Helper Methods
# ============================================================================

def generate_items(count)
  Array.new(count) do |i|
    Item.new(id: i + 1, name: "Item #{i + 1}", value: (i + 1) * 1.5)
  end
end

def generate_xml(items)
  items_xml = items.map do |item|
    %(<item id="#{item.id}"><name>#{item.name}</name><value>#{item.value}</value></item>)
  end.join("\n  ")
  "<container>\n  #{items_xml}\n</container>"
end

def generate_json(items)
  { items: items.map do |i|
    { id: i.id, name: i.name, value: i.value }
  end }.to_json
end

def benchmark_operation(name, iterations: ITERATIONS, warmup: WARMUP, &block)
  # Warmup
  warmup.times(&block)

  # Force GC
  GC.start

  # Benchmark
  total_time = Benchmark.measure do
    iterations.times(&block)
  end.real

  avg_ms = (total_time / iterations) * 1000
  ops_per_sec = iterations / total_time

  {
    name: name,
    iterations: iterations,
    total_time: total_time,
    avg_ms: avg_ms,
    ops_per_sec: ops_per_sec,
  }
end

def print_result(result)
  puts format(
    "  %-40s %8.3f ms %10.0f ops/sec",
    result[:name],
    result[:avg_ms],
    result[:ops_per_sec],
  )
end

# ============================================================================
# Main Benchmark
# ============================================================================

puts "=" * 70
puts "LutaML Model Quick Benchmark"
puts "=" * 70
puts "Ruby: #{RUBY_VERSION} (#{RUBY_ENGINE})"
puts "Iterations: #{ITERATIONS}"
puts "Warmup: #{WARMUP}"
puts

results = []

# Single item operations
puts "Single Item Operations:"
puts "-" * 70

item = Item.new(id: 1, name: "Test Item", value: 99.99)
item_xml = '<item id="1"><name>Test Item</name><value>99.99</value></item>'
item_json = '{"id":1,"name":"Test Item","value":99.99}'

results << benchmark_operation("XML Serialization (single item)") do
  item.to_xml
end
results << benchmark_operation("XML Deserialization (single item)") do
  Item.from_xml(item_xml)
end
results << benchmark_operation("JSON Serialization (single item)") do
  item.to_json
end
results << benchmark_operation("JSON Deserialization (single item)") do
  Item.from_json(item_json)
end

results.each { |r| print_result(r) }
puts

# Small collection (10 items)
puts "Small Collection (10 items):"
puts "-" * 70
small_results = []

small_items = generate_items(10)
small_container = Container.new(items: small_items)
small_xml = generate_xml(small_items)
small_json = generate_json(small_items)

small_results << benchmark_operation("XML Serialization (10 items)") do
  small_container.to_xml
end
small_results << benchmark_operation("XML Deserialization (10 items)") do
  Container.from_xml(small_xml)
end
small_results << benchmark_operation("JSON Serialization (10 items)") do
  small_container.to_json
end
small_results << benchmark_operation("JSON Deserialization (10 items)") do
  Container.from_json(small_json)
end

small_results.each { |r| print_result(r) }
results.concat(small_results)
puts

# Medium collection (50 items)
puts "Medium Collection (50 items):"
puts "-" * 70
medium_results = []

medium_items = generate_items(50)
medium_container = Container.new(items: medium_items)
medium_xml = generate_xml(medium_items)
medium_json = generate_json(medium_items)

medium_results << benchmark_operation("XML Serialization (50 items)") do
  medium_container.to_xml
end
medium_results << benchmark_operation("XML Deserialization (50 items)") do
  Container.from_xml(medium_xml)
end
medium_results << benchmark_operation("JSON Serialization (50 items)") do
  medium_container.to_json
end
medium_results << benchmark_operation("JSON Deserialization (50 items)") do
  Container.from_json(medium_json)
end

medium_results.each { |r| print_result(r) }
results.concat(medium_results)
puts

# Large collection (100 items)
puts "Large Collection (100 items):"
puts "-" * 70
large_results = []

large_items = generate_items(100)
large_container = Container.new(items: large_items)
large_xml = generate_xml(large_items)
large_json = generate_json(large_items)

large_results << benchmark_operation("XML Serialization (100 items)",
                                     iterations: 500) do
  large_container.to_xml
end
large_results << benchmark_operation("XML Deserialization (100 items)",
                                     iterations: 500) do
  Container.from_xml(large_xml)
end
large_results << benchmark_operation("JSON Serialization (100 items)",
                                     iterations: 500) do
  large_container.to_json
end
large_results << benchmark_operation("JSON Deserialization (100 items)",
                                     iterations: 500) do
  Container.from_json(large_json)
end

large_results.each { |r| print_result(r) }
results.concat(large_results)
puts

# Memory estimation
puts "Memory Estimation:"
puts "-" * 70

# Count object allocations
GC.start
before_objects = ObjectSpace.count_objects

1000.times { Item.new(id: 1, name: "Test", value: 1.0) }

after_objects = ObjectSpace.count_objects
allocated = after_objects[:T_OBJECT] - before_objects[:T_OBJECT]
puts "  Objects allocated for 1000 Item.new: ~#{allocated}"

GC.start
item_count = ObjectSpace.each_object(Item).count
puts "  Item objects retained after GC: #{item_count}"

# Summary
puts
puts "=" * 70
puts "SUMMARY"
puts "=" * 70
puts
puts "Performance Comparison (ops/sec):"
puts "-" * 70

xml_results = results.select { |r| r[:name].include?("XML") }
json_results = results.select { |r| r[:name].include?("JSON") }

puts "XML Operations:"
xml_results.each do |r|
  puts format("  %-40s %10.0f", r[:name], r[:ops_per_sec])
end

puts
puts "JSON Operations:"
json_results.each do |r|
  puts format("  %-40s %10.0f", r[:name], r[:ops_per_sec])
end

# Calculate averages
xml_avg = xml_results.sum { |r| r[:ops_per_sec] } / xml_results.size.to_f
json_avg = json_results.sum { |r| r[:ops_per_sec] } / json_results.size.to_f

puts
puts "Average Performance:"
puts format("  XML: %.0f ops/sec", xml_avg)
puts format("  JSON: %.0f ops/sec", json_avg)
puts format("  JSON/XML ratio: %.2fx", json_avg / xml_avg)

puts
puts "Benchmark complete!"
