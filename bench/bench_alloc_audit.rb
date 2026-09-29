# frozen_string_literal: true

require "lutaml/model"

module AllocAudit
  class Row < Lutaml::Model::Serializable
    attribute :id, :integer
    attribute :name, :string

    xml do
      root "row"
      map_element "id", to: :id
      map_element "name", to: :name
    end

    json do
      map "id", to: :id
      map "name", to: :name
    end
  end

  class Doc < Lutaml::Model::Serializable
    attribute :rows, AllocAudit::Row, collection: true

    xml do
      root "doc"
      map_element "row", to: :rows
    end

    json do
      map "rows", to: :rows
    end
  end

  DOC = Doc.new(rows: Array.new(500) { |i| Row.new(id: i, name: "n#{i}") })

  def self.alloc
    GC.start
    before = GC.stat(:total_allocated_objects)
    yield
    GC.stat(:total_allocated_objects) - before
  end

  3.times do
    DOC.to_xml
    DOC.to_json
    DOC.to_hash
  end

  puts "rows=500"
  puts "to_xml_alloc=#{alloc { DOC.to_xml }}"
  puts "to_json_alloc=#{alloc { DOC.to_json }}"
  puts "to_hash_alloc=#{alloc { DOC.to_hash }}"
  puts "from_xml_alloc=#{alloc { Doc.from_xml(DOC.to_xml) }}"
  puts "from_json_alloc=#{alloc { Doc.from_json(DOC.to_json) }}"
end
