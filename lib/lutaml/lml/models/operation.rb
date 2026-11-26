# frozen_string_literal: true

module Lutaml
  module Lml
    # A class operation with parameters and a return type.
    class Operation < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      # From TopElement
      attribute :name, :string
      attribute :definition, Lutaml::Lml::Types::TextType
      attribute :keyword, :string
      attribute :stereotype, :string, collection: true, default: -> { [] }
      attribute :visibility, :string, default: "public"

      # From Operation
      attribute :id, :string
      attribute :return_type, :string
      attribute :parameter_type, :string
      attribute :is_static, :boolean, default: false
      attribute :is_abstract, :boolean, default: false
      attribute :owned_parameter, "Lutaml::Lml::OperationParameter", collection: true,
                                                                     default: -> { [] }
    end
  end
end
