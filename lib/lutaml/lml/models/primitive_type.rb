# frozen_string_literal: true

module Lutaml
  module Lml
    # A primitive type declaration.
    class PrimitiveType < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      # Primitives in LML are name-only entities, but the formatter
      # accesses the same attributes as DataType via format_class.
      attribute :name, :string
      attribute :keyword, :string, default: "primitive"
      attribute :definition, Lutaml::Lml::Types::TextType
      attribute :stereotype, :string, collection: true, default: -> { [] }
      attribute :visibility, :string, default: "public"
      attribute :is_abstract, :boolean, default: false
      attribute :attributes, "Lutaml::Lml::TopElementAttribute", collection: true,
                                                                 default: -> { [] }
      attribute :operations, "Lutaml::Lml::Operation", collection: true,
                                                       default: -> { [] }
      attribute :associations, "Lutaml::Lml::Association", collection: true,
                                                           default: -> { [] }

      def self.entity_type
        :primitives
      end

      def self.classifiable?
        true
      end
    end
  end
end
