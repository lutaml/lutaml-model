# frozen_string_literal: true

require "lutaml/model"

# Source models with hand-written `with:` hooks and a dynamic polymorphic
# class map. `calls` records every source hook or default Proc that runs:
# export and import must leave it empty.
module LmlSerializationHookFixtures
  def self.calls
    @calls ||= []
  end

  class Measure < Lutaml::Model::Serializable
    attribute :amount, :integer
    attribute :category, :string
    attribute :note, :string

    key_value do
      map "amount", to: :amount
      map "category", with: { to: :category_to_kv, from: :category_from_kv }
      map "note", with: { to: :note_to_kv, from: :note_from_kv }
    end

    def category_to_kv(_model, _doc)
      LmlSerializationHookFixtures.calls << :category_to
    end

    def category_from_kv(_model, _value)
      LmlSerializationHookFixtures.calls << :category_from
    end

    def note_to_kv(_model, _doc)
      LmlSerializationHookFixtures.calls << :note_to
    end

    def note_from_kv(_model, _value)
      LmlSerializationHookFixtures.calls << :note_from
    end
  end

  class Plain < Lutaml::Model::Serializable
    attribute :name, :string

    key_value do
      map "name", to: :name
    end
  end

  class XmlHook < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "xmlHook"
      map_element "name", with: { to: :name_to_xml, from: :name_from_xml }
    end

    def name_to_xml(_model, _parent, _doc); end

    def name_from_xml(_model, _node); end
  end

  class Shape < Lutaml::Model::Serializable
    attribute :__kind, :string, polymorphic_class: true
  end

  class Circle < Shape
    attribute :radius, :integer

    key_value do
      map "__kind", to: :__kind
      map "radius", to: :radius
    end
  end

  class Square < Shape
    attribute :side, :integer

    key_value do
      map "__kind", to: :__kind
      map "side", to: :side
    end
  end

  # An opaque, self-filling class map, like Plurimath's NODE_CLASS_MAP.
  DYNAMIC_MAP = Hash.new do |map, name|
    LmlSerializationHookFixtures.calls << :default_proc
    map[name] = name if name.to_s.start_with?("LmlSerializationHookFixtures::")
  end

  class DynamicHolder < Lutaml::Model::Serializable
    attribute :shape, Shape, polymorphic: true

    key_value do
      map "shape", to: :shape, polymorphic: { attribute: "__kind", class_map: DYNAMIC_MAP }
    end
  end

  class StaticHolder < Lutaml::Model::Serializable
    attribute :shape, Shape, polymorphic: true

    key_value do
      map "shape", to: :shape,
                   polymorphic: { attribute: "__kind", class_map: { "circle" => "LmlSerializationHookFixtures::Circle" } }
    end
  end
end
