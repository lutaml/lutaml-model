# frozen_string_literal: true

require "lutaml/model"

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
end
