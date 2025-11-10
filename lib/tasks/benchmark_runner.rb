# frozen_string_literal: true

require "benchmark/ips"

# Ensure lib/ is on the load path regardless of tmp location
lib_path = File.expand_path(File.join(__dir__, "..", "..", "lib"))
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

require "lutaml/model"

class BenchmarkRunner
  def initialize(run_time: nil, items: nil, format: nil, adapter: nil, direction: nil)
    @run_time = run_time || 5
    @items = items || 10
    @format = format
    @adapter = adapter
    @direction = direction
    @label = self.class.name.split("::")[1]

    set_adapter
  end

  def from_format
    input = generate_data

    time_runs { BenchRoot.send("from_#{@format}", input) }
  end

  def to_format
    model = generate_model

    time_runs { model.send("to_#{@format}") }
  end

  def run_benchmarks
    if @direction == :from
      from_format
    elsif @direction == :to
      to_format
    end
  end

  private

  def generate_data
    case @format
    when :xml
      generate_xml
    when :json
      generate_json
    when :yaml
      generate_yaml
    when :toml
      generate_toml
    else
      raise "Unknown format #{@format}"
    end
  end

  def generate_xml
    items = (0...@items).map do |i|
      "<item id='#{i}'><name>Test #{i}</name><value>#{i}</value></item>"
    end
    "<root>#{items.join}</root>"
  end

  def generate_json
    items = (0...@items).map { |i| { "id" => i, "name" => "Test #{i}", "value" => i } }
    { "item" => items }.to_json
  end

  def generate_yaml
    items = (0...@items).map { |i| "  - id: #{i}\n    name: 'Test #{i}'\n    value: #{i}" }
    "item:\n#{items.join("\n")}"
  end

  def generate_toml
    items = (0...@items).map do |i|
      "[[item]]\nid = #{i}\nname = \"Test #{i}\"\nvalue = #{i}\n"
    end
    items.join("\n")
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

    key_value do
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

    key_value do
      map "item", to: :item
    end
  end

  def time_runs(&block)
    job = Benchmark::IPS::Job.new
    job.config(time: @run_time, warmup: 5)
    job.report("#{@label} #{@adapter} #{@direction}_#{@format}", &block)
    job.run

    entry = job.full_report.entries.first
    samples = entry.stats.samples

    raise "No samples collected for #{@format}::#{@adapter} #{@direction}" if samples.empty?

    mean = samples.sum.to_f / samples.size
    variance = samples.sum { |x| (x - mean)**2 } / (samples.size - 1)
    std_dev = Math.sqrt(variance)
    error_margin = std_dev / mean

    error_percentage = error_margin.round(4)
    lower = mean.round(4) * (1 - error_percentage)
    upper = mean.round(4) * (1 + error_percentage)

    result = { lower: lower, upper: upper }
    { "#{@adapter}_#{@direction}_#{@format}": result }
  end

  def set_adapter
    raise ArgumentError, "Format or adapter is not set" if @format.nil? || @adapter.nil?

    Lutaml::Model::Config.public_send("#{@format}_adapter_type=", @adapter)
  end

  def generate_model
    root = BenchRoot.new
    root.item = (0...@items).map { |i| BenchItem.new(id: i, name: "Test #{i}", value: i) }
    root
  end
end
