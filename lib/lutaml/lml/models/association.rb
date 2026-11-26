# frozen_string_literal: true

module Lutaml
  module Lml
    # A relationship between two class ends.
    class Association < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      # From TopElement
      attribute :name, :string
      attribute :definition, Lutaml::Lml::Types::TextType
      attribute :keyword, :string
      attribute :stereotype, :string, collection: true, default: -> { [] }
      attribute :visibility, :string, default: "public"

      # From Association
      attribute :owner_end, :string
      attribute :owner_end_attribute_name, :string
      attribute :owner_end_cardinality, "Lutaml::Lml::Cardinality"
      attribute :owner_end_type, :string
      attribute :member_end, :string
      attribute :member_end_attribute_name, :string
      attribute :member_end_cardinality, "Lutaml::Lml::Cardinality"
      attribute :member_end_type, :string
      attribute :static, :string
      attribute :action, "Lutaml::Lml::Action"
    end
  end
end
