# frozen_string_literal: true

require "json"
require "benchmark/ips"
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

class BenchRunner
  def initialize(run_time: nil, items: nil, format: nil, adapter: nil, direction: nil)
    @run_time = run_time || 5
    @items = items || 10
    @format = format
    @adapter = adapter
    @direction = direction
    @label = self.class.name.split("::").first

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
    "<root>#{(0...@items).map { |i| "<item id='#{i}'><name>Test #{i}</name><value>#{i}</value></item>" }.join}</root>"
  end

  def generate_json
    {
      "item" => (0...@items).map { |i| { "id" => i, "name" => "Test #{i}", "value" => i } },
    }.to_json
  end

  def generate_yaml
    [
      "item:",
      (0...@items).map { |i| "  - id: #{i}\n    name: 'Test #{i}'\n    value: #{i}" },
    ].flatten.join("\n")
  end

  def generate_toml
    (0...@items).flat_map do |i|
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

  def time_runs(&block)
    job = Benchmark::IPS::Job.new
    job.config(time: @run_time, warmup: 5)
    job.report("#{@label} #{@format}::#{@adapter} #{@direction}_#{@format}", &block)
    job.run
    entry = job.full_report.entries.first
    samples = entry.stats.samples
    mean = samples.sum / samples.size
    variance = samples.sum { |x| (x - mean)**2 } / (samples.size - 1)
    std_dev = Math.sqrt(variance)
    error_margin = (std_dev / mean)

    lower = mean.round(4) * (1 - ((error_margin * 100).round(2) / 100.0))
    upper = mean.round(4) * (1 + ((error_margin * 100).round(2) / 100.0))

    result = { lower: lower, upper: upper }

    { "#{@format}_#{@adapter}_#{@direction}_#{@format}": result }
  end

  def set_adapter
    raise "Format or adapter is not set" if @format.nil? || @adapter.nil?

    Lutaml::Model::Config.send("#{@format}_adapter_type=", @adapter)
  end

  def generate_model
    root = BenchRoot.new

    root.item = (0...@items).map do |i|
      BenchItem.new(id: i, name: "Test #{i}", value: i)
    end

    root
  end
end
