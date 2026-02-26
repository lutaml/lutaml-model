# frozen_string_literal: true

# Lutaml::Model Benchmark Suite
#
# This benchmark suite measures serialization and deserialization performance
# across different formats (XML, JSON, YAML) and data sizes.
#
# Usage:
#   bundle exec ruby benchmark/serialization_benchmark.rb
#
# Environment variables:
#   BENCHMARK_ITERATIONS - Number of iterations (default: 100)
#   BENCHMARK_WARMUP     - Number of warmup iterations (default: 10)
#   BENCHMARK_MEMORY     - Enable memory profiling (default: true)
#

require "bundler/setup"
require "lutaml/model"
require "benchmark/ips"
require "memory_profiler"
require "json"
require "yaml"

# Configure adapters
Lutaml::Model.configure do |config|
  config.xml_adapter = :nokogiri
  config.json_adapter = :standard
  config.yaml_adapter = :standard
end

# ============================================================================
# Test Models
# ============================================================================

# Simple model with basic attributes
class SimpleModel < Lutaml::Model::Serializable
  attribute :id, :integer
  attribute :name, :string
  attribute :active, :boolean
  attribute :created_at, :datetime

  xml do
    root "simple"
    map_attribute "id", to: :id
    map_element "name", to: :name
    map_element "active", to: :active
    map_element "created_at", to: :created_at
  end

  json do
    map "id", to: :id
    map "name", to: :name
    map "active", to: :active
    map "created_at", to: :created_at
  end

  yaml do
    map "id", to: :id
    map "name", to: :name
    map "active", to: :active
    map "created_at", to: :created_at
  end
end

# Nested model for testing complex structures
class AddressModel < Lutaml::Model::Serializable
  attribute :street, :string
  attribute :city, :string
  attribute :country, :string
  attribute :postal_code, :string

  xml do
    root "address"
    map_element "street", to: :street
    map_element "city", to: :city
    map_element "country", to: :country
    map_element "postal_code", to: :postal_code
  end

  json do
    map "street", to: :street
    map "city", to: :city
    map "country", to: :country
    map "postal_code", to: :postal_code
  end
end

# Complex model with nested attributes and collections
class PersonModel < Lutaml::Model::Serializable
  attribute :id, :integer
  attribute :first_name, :string
  attribute :last_name, :string
  attribute :email, :string
  attribute :age, :integer
  attribute :address, AddressModel
  attribute :phone_numbers, :string, collection: true
  attribute :tags, :string, collection: true

  xml do
    root "person"
    map_attribute "id", to: :id
    map_element "first_name", to: :first_name
    map_element "last_name", to: :last_name
    map_element "email", to: :email
    map_element "age", to: :age
    map_element "address", to: :address
    map_element "phone_number", to: :phone_numbers
    map_element "tag", to: :tags
  end

  json do
    map "id", to: :id
    map "first_name", to: :first_name
    map "last_name", to: :last_name
    map "email", to: :email
    map "age", to: :age
    map "address", to: :address
    map "phone_numbers", to: :phone_numbers
    map "tags", to: :tags
  end
end

# Deeply nested model for stress testing
class DepartmentModel < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :code, :string
  attribute :employees, PersonModel, collection: true

  xml do
    root "department"
    map_element "name", to: :name
    map_element "code", to: :code
    map_element "employee", to: :employees
  end

  json do
    map "name", to: :name
    map "code", to: :code
    map "employees", to: :employees
  end
end

# ============================================================================
# Test Data Generation
# ============================================================================

module TestData
  class << self
    def simple_model
      SimpleModel.new(
        id: 12345,
        name: "Test Model Name",
        active: true,
        created_at: Time.now,
      )
    end

    def simple_xml
      <<~XML
        <simple id="12345">
          <name>Test Model Name</name>
          <active>true</active>
          <created_at>#{Time.now.iso8601}</created_at>
        </simple>
      XML
    end

    def simple_json
      {
        id: 12345,
        name: "Test Model Name",
        active: true,
        created_at: Time.now.iso8601,
      }.to_json
    end

    def simple_yaml
      {
        id: 12345,
        name: "Test Model Name",
        active: true,
        created_at: Time.now.iso8601,
      }.to_yaml
    end

    def person_model
      PersonModel.new(
        id: 1,
        first_name: "John",
        last_name: "Doe",
        email: "john.doe@example.com",
        age: 30,
        address: AddressModel.new(
          street: "123 Main St",
          city: "New York",
          country: "USA",
          postal_code: "10001",
        ),
        phone_numbers: ["+1-555-123-4567", "+1-555-987-6543"],
        tags: %w[developer ruby lutaml],
      )
    end

    def person_xml
      <<~XML
        <person id="1">
          <first_name>John</first_name>
          <last_name>Doe</last_name>
          <email>john.doe@example.com</email>
          <age>30</age>
          <address>
            <street>123 Main St</street>
            <city>New York</city>
            <country>USA</country>
            <postal_code>10001</postal_code>
          </address>
          <phone_number>+1-555-123-4567</phone_number>
          <phone_number>+1-555-987-6543</phone_number>
          <tag>developer</tag>
          <tag>ruby</tag>
          <tag>lutaml</tag>
        </person>
      XML
    end

    def person_json
      {
        id: 1,
        first_name: "John",
        last_name: "Doe",
        email: "john.doe@example.com",
        age: 30,
        address: {
          street: "123 Main St",
          city: "New York",
          country: "USA",
          postal_code: "10001",
        },
        phone_numbers: ["+1-555-123-4567", "+1-555-987-6543"],
        tags: %w[developer ruby lutaml],
      }.to_json
    end

    def department_model(employee_count: 10)
      employees = Array.new(employee_count) do |i|
        PersonModel.new(
          id: i + 1,
          first_name: "First#{i}",
          last_name: "Last#{i}",
          email: "employee#{i}@example.com",
          age: 25 + (i % 40),
          address: AddressModel.new(
            street: "#{i + 100} Oak Ave",
            city: "City#{i % 5}",
            country: "Country",
            postal_code: format("%05d", i * 111),
          ),
          phone_numbers: ["+1-555-#{format('%03d', i)}-0001"],
          tags: ["tag#{i % 3}"],
        )
      end

      DepartmentModel.new(
        name: "Engineering",
        code: "ENG",
        employees: employees,
      )
    end

    def department_xml(employee_count: 10)
      employees_xml = Array.new(employee_count) do |i|
        <<~XML
          <employee id="#{i + 1}">
            <first_name>First#{i}</first_name>
            <last_name>Last#{i}</last_name>
            <email>employee#{i}@example.com</email>
            <age>#{25 + (i % 40)}</age>
            <address>
              <street>#{i + 100} Oak Ave</street>
              <city>City#{i % 5}</city>
              <country>Country</country>
              <postal_code>#{format('%05d', i * 111)}</postal_code>
            </address>
            <phone_number>+1-555-#{format('%03d', i)}-0001</phone_number>
            <tag>tag#{i % 3}</tag>
          </employee>
        XML
      end.join

      <<~XML
        <department>
          <name>Engineering</name>
          <code>ENG</code>
          #{employees_xml}
        </department>
      XML
    end

    def department_json(employee_count: 10)
      employees = Array.new(employee_count) do |i|
        {
          id: i + 1,
          first_name: "First#{i}",
          last_name: "Last#{i}",
          email: "employee#{i}@example.com",
          age: 25 + (i % 40),
          address: {
            street: "#{i + 100} Oak Ave",
            city: "City#{i % 5}",
            country: "Country",
            postal_code: format("%05d", i * 111),
          },
          phone_numbers: ["+1-555-#{format('%03d', i)}-0001"],
          tags: ["tag#{i % 3}"],
        }
      end

      {
        name: "Engineering",
        code: "ENG",
        employees: employees,
      }.to_json
    end
  end
end

# ============================================================================
# Benchmark Configuration
# ============================================================================

ITERATIONS = (ENV.fetch("BENCHMARK_ITERATIONS", 100)).to_i
WARMUP = (ENV.fetch("BENCHMARK_WARMUP", 10)).to_i
MEMORY_PROFILING = ENV.fetch("BENCHMARK_MEMORY", "true") == "true"

# ============================================================================
# Benchmark Runner
# ============================================================================

class BenchmarkRunner
  def initialize
    @results = {}
  end

  def run_benchmark(name, &block)
    puts "\n#{'=' * 60}"
    puts "Benchmark: #{name}"
    puts "=" * 60

    # Warmup
    puts "Warming up (#{WARMUP} iterations)..."
    WARMUP.times { block.call }

    # Speed benchmark
    puts "\nSpeed Benchmark (#{ITERATIONS} iterations):"
    time = Benchmark.measure do
      ITERATIONS.times { block.call }
    end

    avg_time = time.real / ITERATIONS * 1000 # ms
    ops_per_sec = ITERATIONS / time.real

    puts "  Total time: #{format('%.3f', time.real)}s"
    puts "  Average time: #{format('%.3f', avg_time)}ms"
    puts "  Operations/sec: #{format('%.0f', ops_per_sec)}"

    @results[name] = {
      total_time: time.real,
      avg_time_ms: avg_time,
      ops_per_sec: ops_per_sec,
    }

    # Memory benchmark
    if MEMORY_PROFILING
      puts "\nMemory Benchmark:"
      run_memory_benchmark(&block)
    end

    @results[name]
  end

  def run_memory_benchmark(&block)
    # Force GC before measurement
    GC.start
    GC.compact if GC.respond_to?(:compact)

    result = MemoryProfiler.report do
      10.times { block.call }
    end

    result.pretty_print(scale_bytes: true, normalize_paths: true)

    @results[:memory] ||= {}
    @results[:memory][caller_locations(1..1).first.label] = {
      total_allocated: result.total_allocated,
      total_retained: result.total_retained,
      allocated_memory: result.allocated_memory,
      retained_memory: result.retained_memory,
    }
  rescue StandardError => e
    puts "  Memory profiling skipped: #{e.message}"
  end

  def print_summary
    puts "\n#{'=' * 60}"
    puts "SUMMARY"
    puts "=" * 60

    # Group by operation type
    serialization = @results.select { |k, _| k.to_s.include?("to_") }
    deserialization = @results.select { |k, _| k.to_s.include?("from_") }

    puts "\nSerialization Performance (ops/sec):"
    serialization.each do |name, data|
      puts "  #{name}: #{format('%.0f', data[:ops_per_sec])}"
    end

    puts "\nDeserialization Performance (ops/sec):"
    deserialization.each do |name, data|
      puts "  #{name}: #{format('%.0f', data[:ops_per_sec])}"
    end

    puts "\nPerformance Summary Table:"
    puts "-" * 60
    puts format("%-35s %10s %10s", "Benchmark", "Avg (ms)", "Ops/sec")
    puts "-" * 60
    @results.each do |name, data|
      next if name == :memory

      puts format("%-35s %10.3f %10.0f", name, data[:avg_time_ms], data[:ops_per_sec])
    end
    puts "-" * 60
  end
end

# ============================================================================
# Main Benchmark Execution
# ============================================================================

def main
  puts "LutaML Model Serialization Benchmark Suite"
  puts "=" * 60
  puts "Configuration:"
  puts "  Iterations: #{ITERATIONS}"
  puts "  Warmup: #{WARMUP}"
  puts "  Memory Profiling: #{MEMORY_PROFILING}"
  puts "  Ruby: #{RUBY_VERSION}"
  puts "  RUBY_ENGINE: #{RUBY_ENGINE}"

  runner = BenchmarkRunner.new

  # ==========================================================================
  # Simple Model Benchmarks
  # ==========================================================================

  puts "\n" + "=" * 60
  puts "SIMPLE MODEL BENCHMARKS"
  puts "=" * 60

  simple = TestData.simple_model
  simple_xml = TestData.simple_xml
  simple_json = TestData.simple_json
  simple_yaml = TestData.simple_yaml

  runner.run_benchmark("Simple XML Serialization (to_xml)") do
    simple.to_xml
  end

  runner.run_benchmark("Simple XML Deserialization (from_xml)") do
    SimpleModel.from_xml(simple_xml)
  end

  runner.run_benchmark("Simple JSON Serialization (to_json)") do
    simple.to_json
  end

  runner.run_benchmark("Simple JSON Deserialization (from_json)") do
    SimpleModel.from_json(simple_json)
  end

  runner.run_benchmark("Simple YAML Serialization (to_yaml)") do
    simple.to_yaml
  end

  runner.run_benchmark("Simple YAML Deserialization (from_yaml)") do
    SimpleModel.from_yaml(simple_yaml)
  end

  # ==========================================================================
  # Complex Model Benchmarks
  # ==========================================================================

  puts "\n" + "=" * 60
  puts "COMPLEX MODEL BENCHMARKS (Person with nested Address)"
  puts "=" * 60

  person = TestData.person_model
  person_xml = TestData.person_xml
  person_json = TestData.person_json

  runner.run_benchmark("Person XML Serialization (to_xml)") do
    person.to_xml
  end

  runner.run_benchmark("Person XML Deserialization (from_xml)") do
    PersonModel.from_xml(person_xml)
  end

  runner.run_benchmark("Person JSON Serialization (to_json)") do
    person.to_json
  end

  runner.run_benchmark("Person JSON Deserialization (from_json)") do
    PersonModel.from_json(person_json)
  end

  # ==========================================================================
  # Collection Benchmarks
  # ==========================================================================

  puts "\n" + "=" * 60
  puts "COLLECTION BENCHMARKS (Department with 10 employees)"
  puts "=" * 60

  dept_small = TestData.department_model(employee_count: 10)
  dept_small_xml = TestData.department_xml(employee_count: 10)
  dept_small_json = TestData.department_json(employee_count: 10)

  runner.run_benchmark("Department(10) XML Serialization") do
    dept_small.to_xml
  end

  runner.run_benchmark("Department(10) XML Deserialization") do
    DepartmentModel.from_xml(dept_small_xml)
  end

  runner.run_benchmark("Department(10) JSON Serialization") do
    dept_small.to_json
  end

  runner.run_benchmark("Department(10) JSON Deserialization") do
    DepartmentModel.from_json(dept_small_json)
  end

  # ==========================================================================
  # Large Collection Benchmarks
  # ==========================================================================

  puts "\n" + "=" * 60
  puts "LARGE COLLECTION BENCHMARKS (Department with 50 employees)"
  puts "=" * 60

  dept_large = TestData.department_model(employee_count: 50)
  dept_large_xml = TestData.department_xml(employee_count: 50)
  dept_large_json = TestData.department_json(employee_count: 50)

  runner.run_benchmark("Department(50) XML Serialization") do
    dept_large.to_xml
  end

  runner.run_benchmark("Department(50) XML Deserialization") do
    DepartmentModel.from_xml(dept_large_xml)
  end

  runner.run_benchmark("Department(50) JSON Serialization") do
    dept_large.to_json
  end

  runner.run_benchmark("Department(50) JSON Deserialization") do
    DepartmentModel.from_json(dept_large_json)
  end

  # ==========================================================================
  # Summary
  # ==========================================================================

  runner.print_summary

  puts "\nBenchmark complete!"
end

main if __FILE__ == $PROGRAM_NAME
