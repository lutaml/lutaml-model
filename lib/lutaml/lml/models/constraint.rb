# frozen_string_literal: true

module Lutaml
  module Lml
    # A named constraint on a class.
    class Constraint < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      # From TopElement
      attribute :name, :string
      attribute :definition, Lutaml::Lml::Types::TextType
      attribute :keyword, :string
      attribute :stereotype, :string, collection: true, default: -> { [] }
      attribute :visibility, :string, default: "public"

      # From Constraint
      attribute :body, :string
      attribute :type, :string
      attribute :weight, :string
      attribute :status, :string
    end
  end
end
