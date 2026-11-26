# frozen_string_literal: true

module Lutaml
  module Lml
    # A diagram declaration.
    class Diagram < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      attribute :name, :string
      attribute :definition, Lutaml::Lml::Types::TextType
      attribute :keyword, :string
      attribute :stereotype, :string, collection: true, default: -> { [] }
      attribute :visibility, :string, default: "public"

      attribute :package_id, :string
      attribute :package_name, :string
      attribute :diagram_type, :string
    end
  end
end
