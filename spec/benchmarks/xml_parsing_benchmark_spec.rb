# frozen_string_literal: true

require "spec_helper"
require "benchmark/ips"

# Adapter-comparison benchmark, runnable on demand:
#   bundle exec rspec --tag benchmark spec/benchmarks/
# Tagged out of the default suite (.rsex --tag ~benchmark); asserts
# nothing about absolute speed — machines differ — but prints i/s and
# allocations/op so regressions are visible when run deliberately.
RSpec.describe "XML adapter benchmark", :benchmark do
  Item = Class.new(Lutaml::Model::Serializable) do
    attribute :id, :integer
    attribute :name, :string
    attribute :tags, :string, collection: true

    xml do
      element "item"
      map_attribute "id", to: :id
      map_element "name", to: :name
      map_element "tag", to: :tags
    end
  end

  Root = Class.new(Lutaml::Model::Serializable) do
    attribute :item, Item, collection: true

    xml do
      element "root"
      map_element "item", to: :item
    end
  end

  XML = +"<root>"
  1_000.times { |i| XML << %(<item id="#{i}"><name>Item #{i}</name><tag>a</tag><tag>b</tag></item>) }
  XML << "</root>"

  def allocations_of
    GC.start
    before = GC.stat(:total_allocated_objects)
    yield
    GC.stat(:total_allocated_objects) - before
  end

  %i[nokogiri ox oga rexml leptris].each do |adapter|
    it "#{adapter}: from_xml/to_xml i/s and allocations" do
      model = nil
      Lutaml::Model::Config.with_adapter(xml: adapter) do
        begin
          Lutaml::Model::Config.adapter_for(:xml)
        rescue Lutaml::Model::UnknownAdapterTypeError
          skip "#{adapter} adapter unavailable on this platform"
        end
        report = Benchmark.ips(time: 2, warmup: 1, quiet: true) do |x|
          x.report("parse") { model = Root.from_xml(XML) }
          x.report("serialize") { model.to_xml }
        end
        parse_ips = report.entries.first.ips
        serialize_ips = report.entries.last.ips

        allocs = allocations_of { Root.from_xml(XML) }
        puts format(
          "%<a>-9s parse %<p>7.1f i/s  serialize %<s>7.1f i/s  %<al>8d allocs/op",
          a: adapter, p: parse_ips, s: serialize_ips, al: allocs,
        )
        expect(model.item.size).to eq(1_000)
      end
    end
  end
end
