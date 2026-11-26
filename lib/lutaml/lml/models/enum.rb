# frozen_string_literal: true

module Lutaml
  module Lml
    # An enumeration declaration with its value members.
    class Enum < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      # From TopElement
      attribute :name, :string
      attribute :definition, Lutaml::Lml::Types::TextType
      attribute :keyword, :string, default: "enumeration"
      attribute :stereotype, :string, collection: true, default: -> { [] }
      attribute :visibility, :string, default: "public"

      # From UmlClassifier
      attribute :is_abstract, :boolean, default: false

      # From Enum
      attribute :attributes, "Lutaml::Lml::TopElementAttribute", collection: true,
                                                                 default: -> { [] }
      attribute :modifier, :string
      attribute :member_fields, "Lutaml::Lml::MemberField", collection: true, default: -> { [] }
      attribute :from_table_name, :string
      attribute :from_table_artifact, :string
      attribute :operations, "Lutaml::Lml::Operation", collection: true, default: -> { [] }
      attribute :values, "Lutaml::Lml::Value", collection: true, default: -> { [] }

      def self.entity_type
        :enums
      end

      def self.classifiable?
        false
      end
    end
  end
end
