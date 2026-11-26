# frozen_string_literal: true

module Lutaml
  module Lml
    # An attribute declaration or instance assignment entry.
    class TopElementAttribute < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      # Core attributes
      attribute :name, :string
      attribute :visibility, :string, default: "public"
      attribute :type, :string
      attribute :id, :string
      attribute :contain, :string
      attribute :static, :string
      attribute :cardinality, "Lutaml::Lml::Cardinality"
      attribute :literal, :boolean, default: false
      attribute :is_derived, :boolean, default: false
      attribute :is_static, :boolean, default: false
      attribute :is_read_only, :boolean, default: false
      attribute :stereotype, :string, collection: true, default: -> { [] }
      attribute :definition, Lutaml::Lml::Types::TextType
      attribute :association, :string
      attribute :default, :string
      attribute :value_set, :string, collection: true, default: -> { [] }
      attribute :pattern, :string
      # `as :element` / `as :attribute`: the XML node kind (issue #49)
      attribute :xml_role, :string

      # LML-specific attributes
      attribute :properties, "Lutaml::Lml::TopElementAttribute", collection: true, default: -> { [] }
      attribute :value, LiteralValue
      attribute :attributes, "Lutaml::Lml::TopElementAttribute", collection: true, default: -> { [] }
      attribute :extended, :boolean
      attribute :instances, "Lutaml::Lml::Instance", collection: true, default: -> { [] }

      # Declared in full because a mapping block replaces the defaults. The
      # rules below are the defaults, 1:1, except for `value`.
      #
      # `value` needs custom methods because a list literal reaches the model
      # as a bare Array, and lutaml-model refuses one on a non-collection
      # attribute: Attribute#cast splits it, then valid_collection! raises
      # CollectionTrueMissingError. A custom `from` returns before that check,
      # so a non-empty list survives a round trip without changing the
      # serialized form. An empty list still does not: the transform skips a
      # blank value before reaching the custom method, so `[]` reloads as nil.
      key_value do
        map "name", to: :name
        map "visibility", to: :visibility
        map "type", to: :type
        map "id", to: :id
        map "contain", to: :contain
        map "static", to: :static
        map "cardinality", to: :cardinality
        map "literal", to: :literal
        map "is_derived", to: :is_derived
        map "is_static", to: :is_static
        map "is_read_only", to: :is_read_only
        map "stereotype", to: :stereotype
        map "definition", to: :definition
        map "association", to: :association
        map "default", to: :default
        map "value_set", to: :value_set
        map "pattern", to: :pattern
        map "xml_role", to: :xml_role
        map "properties", to: :properties
        map "value", to: :value, with: { to: :value_to, from: :value_from }
        map "attributes", to: :attributes
        map "extended", to: :extended
        map "instances", to: :instances
      end

      # Public because lutaml-model invokes mapping methods via public_send.
      #
      # Skipping nil keeps the key out of the output, which is what the default
      # mapping does. `false` is a real literal, so the guard tests for nil
      # rather than truthiness.
      def value_to(model, doc)
        literal = model.value
        return if literal.nil?

        doc["value"] = unwrap_literal(literal)
      end

      # lutaml-model runs this on a throwaway mapper instance, so `self` is not
      # the object being deserialized - `model` is. Writing to `self.value`
      # here would update an object that is discarded a moment later.
      def value_from(model, value)
        model.value = value
      end

      # RS 3001 par. Value type: the typed view of a reference value
      # (`reference:(...)` / `ref:(...)`). Nil for every other value shape;
      # for a list of references, the first reference.
      def reference
        literal = value.respond_to?(:value) ? value.value : value
        cargo = literal.is_a?(::Array) ? literal.first : literal
        cargo = cargo.value if cargo.is_a?(LiteralValue)
        return nil unless cargo.is_a?(::Hash) && cargo[:reference]

        Reference.new(path: cargo[:reference].to_s)
      end

      private

      # A LiteralValue sits at the top level for a map literal, and inside the
      # array for a list of references. Writing one through unwrapped raises
      # ArgumentError in the adapter.
      def unwrap_literal(value)
        return value.map { |item| unwrap_literal(item) } if value.is_a?(::Array)

        value.is_a?(LiteralValue) ? value.value : value
      end
    end
  end
end
