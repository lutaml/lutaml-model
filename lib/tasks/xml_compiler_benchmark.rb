# frozen_string_literal: true

require "benchmark/ips"
require "lutaml/model"
require "lutaml/model/schema"

# Ensure Nokogiri adapter is set
Lutaml::Model::Config.xml_adapter_type = :nokogiri

module XmlCompilerBenchmarks
  # Shared test schemas
  SCHEMAS = {
    small: <<~XSD,
      <?xml version="1.0" encoding="UTF-8"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="root" type="RootType"/>
        <xs:complexType name="RootType">
          <xs:sequence>
            <xs:element name="child" type="xs:string" maxOccurs="unbounded"/>
          </xs:sequence>
          <xs:attribute name="id" type="xs:string"/>
        </xs:complexType>
      </xs:schema>
    XSD
    medium: <<~XSD,
      <?xml version="1.0" encoding="UTF-8"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 targetNamespace="http://example.com/test"
                 xmlns:tns="http://example.com/test">
        <xs:element name="document" type="tns:DocumentType"/>
        <xs:complexType name="DocumentType">
          <xs:sequence>
            <xs:element name="header" type="tns:HeaderType"/>
            <xs:element name="body" type="tns:BodyType" maxOccurs="unbounded"/>
          </xs:sequence>
          <xs:attribute name="version" type="xs:string"/>
        </xs:complexType>
        <xs:complexType name="HeaderType">
          <xs:sequence>
            <xs:element name="title" type="xs:string"/>
            <xs:element name="author" type="tns:PersonType" maxOccurs="unbounded"/>
          </xs:sequence>
        </xs:complexType>
        <xs:complexType name="PersonType">
          <xs:sequence>
            <xs:element name="firstName" type="xs:string"/>
            <xs:element name="lastName" type="xs:string"/>
          </xs:sequence>
          <xs:attribute name="id" type="xs:ID"/>
        </xs:complexType>
        <xs:complexType name="BodyType">
          <xs:sequence>
            <xs:element name="section" type="tns:SectionType" maxOccurs="unbounded"/>
          </xs:sequence>
        </xs:complexType>
        <xs:complexType name="SectionType">
          <xs:sequence>
            <xs:element name="heading" type="xs:string"/>
            <xs:choice>
              <xs:element name="paragraph" type="tns:ParagraphType"/>
              <xs:element name="list" type="tns:ListType"/>
            </xs:choice>
          </xs:sequence>
          <xs:attribute name="id" type="xs:ID"/>
        </xs:complexType>
        <xs:complexType name="ParagraphType" mixed="true">
          <xs:sequence>
            <xs:element name="emphasis" type="xs:string" minOccurs="0" maxOccurs="unbounded"/>
          </xs:sequence>
        </xs:complexType>
        <xs:complexType name="ListType">
          <xs:sequence>
            <xs:element name="item" type="xs:string" maxOccurs="unbounded"/>
          </xs:sequence>
        </xs:complexType>
      </xs:schema>
    XSD
  }.freeze

  class << self
    def run_all
      puts "=" * 80
      puts "XML Compiler Performance Benchmarks"
      puts "=" * 80
      puts

      benchmark_code_generation
      benchmark_string_operations
      benchmark_module_handling
    end

    def benchmark_code_generation
      puts "-" * 40
      puts "Code Generation Benchmark"
      puts "-" * 40

      job = Benchmark::IPS::Job.new
      job.config(time: 5, warmup: 2)

      job.report("to_models(small)") do
        Lutaml::Model::Schema::XmlCompiler.to_models(
          SCHEMAS[:small],
          load_classes: false,
          create_files: false,
          module_namespace: "Small",
        )
      end

      job.report("to_models(medium)") do
        Lutaml::Model::Schema::XmlCompiler.to_models(
          SCHEMAS[:medium],
          load_classes: false,
          create_files: false,
          module_namespace: "Medium",
        )
      end

      job.run
      puts
    end

    def benchmark_string_operations
      puts "-" * 40
      puts "String Operations Benchmark"
      puts "-" * 40

      job = Benchmark::IPS::Job.new
      job.config(time: 3, warmup: 1)

      job.report("Utils.camel_case") do
        Lutaml::Model::Utils.camel_case("test_string")
        Lutaml::Model::Utils.camel_case("another_test")
      end

      job.report("Utils.snake_case") do
        Lutaml::Model::Utils.snake_case("TestString")
        Lutaml::Model::Utils.snake_case("AnotherTest")
      end

      job.report("split(':') + last") do
        "foo:Bar:Baz".split(":").last
      end

      job.run
      puts
    end

    def benchmark_module_handling
      puts "-" * 40
      puts "Module Namespace Handling Benchmark"
      puts "-" * 40

      job = Benchmark::IPS::Job.new
      job.config(time: 3, warmup: 1)

      deep_namespace = "Foo::Bar::Baz::Qux"

      job.report("split each time") do
        deep_namespace.split("::")
      end

      # Simulated cached version
      cached = deep_namespace.split("::")
      job.report("cached modules") do
        cached.map { |m| m }
      end

      job.run
      puts
    end
  end
end

# Runner class compatible with existing infrastructure
class XmlCompilerBenchmarkRunner
  def initialize(run_time: nil, **)
    @run_time = run_time || 5
    @schemas = XmlCompilerBenchmarks::SCHEMAS
  end

  def run_benchmarks
    results = {}

    job = Benchmark::IPS::Job.new
    job.config(time: @run_time, warmup: 2)

    job.report("xml_compiler_small") do
      Lutaml::Model::Schema::XmlCompiler.to_models(
        @schemas[:small],
        load_classes: false,
        create_files: false,
        module_namespace: "Small",
      )
    end

    job.report("xml_compiler_medium") do
      Lutaml::Model::Schema::XmlCompiler.to_models(
        @schemas[:medium],
        load_classes: false,
        create_files: false,
        module_namespace: "Medium",
      )
    end

    job.run

    job.full_report.entries.each do |entry|
      samples = entry.stats.samples
      mean = samples.sum.to_f / samples.size
      variance = samples.sum { |x| (x - mean)**2 } / (samples.size - 1)
      std_dev = Math.sqrt(variance)
      error_margin = std_dev / mean

      lower = (mean * (1 - error_margin)).round(4)
      upper = (mean * (1 + error_margin)).round(4)

      results[entry.label.to_sym] = { lower: lower, upper: upper }
    end

    results
  end
end

if __FILE__ == $PROGRAM_NAME
  XmlCompilerBenchmarks.run_all
end
