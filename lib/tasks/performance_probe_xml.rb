# frozen_string_literal: true

# XML pipeline probe (mirrors performance_probe.rb's KV shape): quantifies
# the lutaml-model XML layer over the moxml runtime-default engine.
#   ruby lib/tasks/performance_probe.rb xml

require "lutaml/model"

item = Class.new(Lutaml::Model::Serializable) do
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
root = Class.new(Lutaml::Model::Serializable) do
  attribute :item, item, collection: true

  xml do
    element "root"
    map_element "item", to: :item
  end
end

model = root.new(item: (0...200).map { |i| item.new(id: i, name: "Test #{i}", tags: %w[a b c]) })
xml_doc = model.to_xml
root.from_xml(xml_doc)

ips = lambda do |label, &blk|
  require "benchmark/ips"
  r = Benchmark.ips(time: 3, quiet: true) { |x| x.report(label, &blk) }
  r.entries.max_by(&:ips).ips.round(1)
end

allocs = lambda do |&blk|
  GC.start
  before = GC.stat(:total_allocated_objects)
  50.times(&blk)
  (GC.stat(:total_allocated_objects) - before) / 50.0
end

fy = ips.call("fx") { root.from_xml(xml_doc) }
fa = allocs.call { root.from_xml(xml_doc) }
ty = ips.call("tx") { model.to_xml }
ta = allocs.call { model.to_xml }

puts format("from_xml: %<ips>8.1f i/s   allocs/op: %<allocs>8.1f", ips: fy, allocs: fa)
puts format("to_xml  : %<ips>8.1f i/s   allocs/op: %<allocs>8.1f", ips: ty, allocs: ta)
puts "engine: #{Moxml::VERSION} / #{Leptris::VERSION}"
