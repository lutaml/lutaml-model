# frozen_string_literal: true

require "lutaml/model"
require "leptris"
require "leptris/xml/descriptor"
require "benchmark"

module PlanWalkProbe
  class BulkItem < Lutaml::Model::Serializable
    attribute :id, :integer
    attribute :name, :string
    attribute :tags, :string, collection: true

    xml do
      element "row"
      map_attribute "id", to: :id
      map_element "name", to: :name
      map_element "tags", to: :tags
    end
  end

  class BulkRoot < Lutaml::Model::Serializable
    attribute :item, BulkItem, collection: true

    xml do
      element "iso"
      map_element "row", to: :item
    end
  end
end

xml = File.read("/tmp/iso.xml")
Lutaml::Model::Config.adapter_for(:xml) # resolve adapter before benchmarking

measure = lambda do |label, &block|
  elapsed = Benchmark.measure { 3.times(&block) }.real * 1000
  puts "#{label}: %.2f ms total / %.2f ms each" % [elapsed, elapsed / 3]
end

measure.call("raw parse + descriptor walk") do
  descriptor = Leptris::XML::Descriptor.build(
    name: "iso",
    children: [{ name: "row", kind: :collection }],
  )
  descriptor.walk(Leptris::XML.parse(xml).root)
end

Lutaml::Model::Config.instance.xml_plan_fast_path = true
measure.call("PlanWalk parse + 5000 model.new") do
  result = Lutaml::Xml::PlanWalk.call(PlanWalkProbe::BulkRoot, xml)
  raise "PlanWalk returned nil" unless result&.item&.size == 5000
end

Lutaml::Model::Config.instance.xml_plan_fast_path = false
measure.call("interpretive from_xml") do
  result = PlanWalkProbe::BulkRoot.from_xml(xml)
  raise "interpretive returned wrong size" unless result.item.size == 5000
end
