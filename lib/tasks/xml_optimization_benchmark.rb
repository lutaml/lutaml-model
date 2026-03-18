# frozen_string_literal: true

require "benchmark/ips"
require_relative "../lutaml/model"
require_relative "../lutaml/xml/adapter/nokogiri_adapter"

# Ensure Nokogiri adapter is set
Lutaml::Model::Config.xml_adapter_type = :nokogiri

class XmlElementBenchmark
  def initialize(run_time: nil, items: nil)
    @run_time = run_time || 10
    @items = items || 100
  end

  def run
    puts "=" * 80
    puts "XmlElement Optimization Benchmarks"
    puts "=" * 80
    puts

    benchmark_child_index
    benchmark_namespaced_name_memoization
    benchmark_children_count
    benchmark_parsing

    puts
    puts "=" * 80
  end

  private

  def generate_xml(depth: 3, items_per_level: 10)
    builder = String.new
    builder << "<root xmlns:ns1='http://example.com/ns1' xmlns:ns2='http://example.com/ns2'>"

    depth.times do |level|
      items_per_level.times do |i|
        builder << "<element ns1:id='#{level}-#{i}' ns2:index='#{i}'>"
        builder << "<child>Text #{level}-#{i}</child>"
        builder << "<child>More text #{level}-#{i}</child>"
        builder << "</element>"
      end
    end

    builder << "</root>"
    builder
  end

  def benchmark_child_index
    puts "-" * 40
    puts "Child Index Benchmark"
    puts "-" * 40

    xml = generate_xml
    doc = Lutaml::Xml::NokogiriAdapter::Document.parse(xml)
    element = doc.root

    job = Benchmark::IPS::Job.new
    job.config(time: @run_time, warmup: 3)

    job.report("find_children_by_name (O(1) with index)") do
      element.find_children_by_name("child")
      element.find_children_by_name("element")
      element.find_child_by_name("child")
      element.find_child_by_name("element")
    end

    job.run
    puts
  end

  def benchmark_namespaced_name_memoization
    puts "-" * 40
    puts "Namespaced Name Memoization Benchmark"
    puts "-" * 40

    xml = generate_xml
    doc = Lutaml::Xml::NokogiriAdapter::Document.parse(xml)

    job = Benchmark::IPS::Job.new
    job.config(time: @run_time, warmup: 3)

    job.report("namespaced_name (memoized)") do
      doc.root.children.each do |child|
        child.namespaced_name
      end
    end

    job.run
    puts
  end

  def benchmark_children_count
    puts "-" * 40
    puts "Children Count Caching Benchmark"
    puts "-" * 40

    xml = generate_xml
    doc = Lutaml::Xml::NokogiriAdapter::Document.parse(xml)

    job = Benchmark::IPS::Job.new
    job.config(time: @run_time, warmup: 3)

    job.report("children_count (cached)") do
      doc.root.children.each do |child|
        count = child.children_count
        count.zero? ? nil : count
      end
    end

    job.run
    puts
  end

  def benchmark_parsing
    puts "-" * 40
    puts "XML Parsing Benchmark"
    puts "-" * 40

    xml = generate_xml

    job = Benchmark::IPS::Job.new
    job.config(time: @run_time, warmup: 3)

    job.report("parse XML (full parse)") do
      Lutaml::Xml::NokogiriAdapter::Document.parse(xml)
    end

    job.run
    puts
  end
end

class CollectionHandlerBenchmark
  def initialize(run_time: nil)
    @run_time = run_time || 10
  end

  def run
    puts "-" * 40
    puts "CollectionHandler Memoization Benchmark"
    puts "-" * 40

    bench_class = Class.new(Lutaml::Model::Serializable) do
      attribute :items, :string, collection: true
      attribute :single, :string
      attribute :custom_coll, :string, collection: SomeCollection
    end

    attr_defs = bench_class.attributes.values

    job = Benchmark::IPS::Job.new
    job.config(time: @run_time, warmup: 3)

    job.report("collection? (memoized)") do
      attr_defs.each { |a| a.collection? }
    end

    job.report("singular? (memoized)") do
      attr_defs.each { |a| a.singular? }
    end

    job.report("collection_class (memoized)") do
      attr_defs.each { |a| a.collection_class }
    end

    job.run
    puts
  end
end

# Custom collection class for testing
class SomeCollection < Lutaml::Model::Collection
end

if __FILE__ == $PROGRAM_NAME
  XmlElementBenchmark.new(run_time: 10).run
  CollectionHandlerBenchmark.new(run_time: 10).run
end
