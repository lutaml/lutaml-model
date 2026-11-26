# frozen_string_literal: true

module Lutaml
  module Lml
    # A class declaration with its members.
    class UmlClass < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      # From TopElement. TextType unescapes \{ \} and normalizes lines
      # on every assignment (builder, yaml, direct).
      attribute :name, :string
      attribute :definition, Lutaml::Lml::Types::TextType
      attribute :stereotype, :string, collection: true, default: -> { [] }
      attribute :visibility, :string, default: "public"
      attribute :comments, :string, collection: true

      # From UmlClassifier
      attribute :is_abstract, :boolean, default: false

      # From UmlClass
      attribute :nested_classifier, :string, collection: true, default: -> { [] }
      attribute :type, :string
      attribute :attributes, "Lutaml::Lml::TopElementAttribute", collection: true
      attribute :modifier, :string
      attribute :constraints, "Lutaml::Lml::Constraint", collection: true
      attribute :operations, "Lutaml::Lml::Operation", collection: true, default: -> { [] }
      attribute :data_types, "Lutaml::Lml::DataType", collection: true
      attribute :associations, "Lutaml::Lml::Association", collection: true
      attribute :wire_mappings, "Lutaml::Lml::Mapping", collection: true, default: -> { [] }
      attribute :string_formats, "Lutaml::Lml::StringFormat", collection: true, default: -> { [] }
      attribute :derived_fields, "Lutaml::Lml::DerivedField", collection: true, default: -> { [] }
      attribute :serialization_mappings, "Lutaml::Lml::SerializationMapping", collection: true, default: -> { [] }

      # LML-specific
      # In-class `namespace "uri"` declaration (issue #49)
      attribute :xml_namespace, "Lutaml::Lml::Namespace"
      attribute :parent_class, :string

      yaml do
        map "name", to: :name
        map "is_abstract", to: :is_abstract
        map "definition", to: :definition
        map "modifier", to: :modifier
        map "stereotype", to: :stereotype
        map "visibility", to: :visibility
        map "type", to: :type
        map "xml_namespace", to: :xml_namespace
        map "attributes", to: :attributes
        map "operations", to: :operations
        map "constraints", to: :constraints
        map "data_types", to: :data_types
        # Owner-side defaulting is a parent-context rule ("an
        # association nested under a class defaults its owner to that
        # class"); only a mapping proc can see the containing model.
        map "associations", to: :associations, with: {
          to: :associations_to_yaml, from: :associations_from_yaml
        }
      end

      def associations_to_yaml(model, doc)
        return unless model.associations

        associations = model.associations.map(&:to_hash)
        doc["associations"] = associations unless associations.empty?
      end

      def associations_from_yaml(model, values)
        associations = values.map do |value|
          value["owner_end"] = model.name if value["owner_end"].nil?
          Association.from_yaml(value.to_yaml)
        end

        model.associations = associations
      end

      def self.entity_type
        :classes
      end

      def self.classifiable?
        true
      end
    end
  end
end
