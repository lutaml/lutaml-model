# frozen_string_literal: true

require "lutaml/model"
require_relative "lml_order_fixtures"

# Named fixtures for the LML exporter: the document addresses models by
# class path, so anonymous classes are unnameable.
module LmlExportFixtures # rubocop:disable Lint/ConstantDefinitionInBlock -- named fixtures
  # Shaped like Mml::V4::Math: ordered content, element collections,
  # no declared sequence.
  class MathShape < Lutaml::Model::Serializable
    attribute :mi, :string, collection: true
    attribute :mn, :string, collection: true

    xml do
      root "math", ordered: true
      map_element "mi", to: :mi
      map_element "mn", to: :mn
    end
  end

  class MixedShape < Lutaml::Model::Serializable
    attribute :content, :string, collection: true

    xml do
      root "p", mixed: true
      map_content to: :content
    end
  end

  class OrderedWithCallback < Lutaml::Model::Serializable
    attribute :a, :string

    xml do
      root "cb", ordered: true
      map_element "a", to: :a, with: { to: :a_to_xml, from: :a_from_xml }
    end

    def a_to_xml(_model, _parent, _doc); end

    def a_from_xml(_model, _value); end
  end

  class ReservedMember < Lutaml::Model::Serializable
    attribute :__lml_content, :string

    xml do
      root "r"
      map_element "x", to: :__lml_content
    end
  end

  class RenderPolicies < Lutaml::Model::Serializable
    attribute :x, :string
    attribute :y, :string

    json do
      map "x", to: :x, render_empty: true
      map "y", to: :y, value_map: { to: { empty: :nil } }
    end
  end

  class PortableRender < Lutaml::Model::Serializable
    attribute :x, :string
    attribute :count, :integer, default: 3
    attribute :kind, :string, values: %w[a b]
    attribute :items, :string, collection: 1..4

    xml do
      root "pr"
      map_element "x", to: :x, render_empty: true, render_nil: :as_blank, render_default: true
      map_attribute "count", to: :count
      map_attribute "kind", to: :kind
      map_element "item", to: :items
    end
  end

  class TransformRule < Lutaml::Model::Serializable
    attribute :x, :string

    json do
      map "x", to: :x, transform: { export: ->(v) { v } }
    end
  end

  class FloatAttr < Lutaml::Model::Serializable
    attribute :f, :float
  end

  class ChildMapped < Lutaml::Model::Serializable
    attribute :schemas, :string, collection: true

    json do
      map "schemas", to: :schemas, child_mappings: { id: :key, path: %i[path link] }
    end
  end

  class RootMapped < Lutaml::Model::Serializable
    attribute :fonts, :string, collection: true

    key_value do
      map to: :fonts, root_mappings: { name: :key, styles: :value }
    end
  end

  class KeyValueOnly < Lutaml::Model::Serializable
    attribute :name, :string

    key_value do
      map "name", to: :name
    end
  end

  class PolyBase < Lutaml::Model::Serializable
    attribute :_class, :string, polymorphic_class: true

    xml do
      map_attribute "item-type", to: :_class, polymorphic_map: {
        "basic" => "LmlExportFixtures::PolyBase",
      }
    end
  end

  class PolyHolder < Lutaml::Model::Serializable
    attribute :items, PolyBase, collection: true

    xml do
      root "holder"
      map_element "item", to: :items, polymorphic: {
        attribute: "type",
        class_map: { "base" => "LmlExportFixtures::PolyBase" },
      }
    end
  end

  class SequencedShape < Lutaml::Model::Serializable
    attribute :a, :string
    attribute :b, :string

    xml do
      root "seq"
      sequence do
        map_element "a", to: :a
        map_element "b", to: :b
      end
    end
  end

  class ChoiceSequence < Lutaml::Model::Serializable
    attribute :a, :string
    attribute :b, :string
    attribute :c, :string

    xml do
      root "cs"
      sequence do
        map_element "a", to: :a
        choice(min: 1, max: 1) do
          map_element "b", to: :b
          map_element "c", to: :c
        end
      end
    end
  end

  # Fixture models the portable exporter must refuse, with the reason.
  REFUSED = {
    "LmlExportFixtures::OrderedWithCallback" => :imperative_element_order,
    "LmlExportFixtures::ReservedMember" => :reserved_member,
    "LmlExportFixtures::TransformRule" => :unsupported_mapping,
    "LmlExportFixtures::FloatAttr" => :unsupported_type,
    "LmlOrderFixtures::ImperativeRule" => :imperative_element_order,
    "LmlOrderFixtures::ReservedMember" => :reserved_member,
  }.freeze

  # Every Serializable fixture in the export and order fixture modules.
  def self.exportable_models
    [self, LmlOrderFixtures].flat_map do |mod|
      mod.constants.map { |name| mod.const_get(name) }
        .select { |c| c.is_a?(Class) && c < Lutaml::Model::Serializable }
    end
  end
end
