# frozen_string_literal: true

module Lutaml
  module Lml
    # A value construct member.
    class Value < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      attribute :name, :string
      attribute :id, :string
      attribute :type, :string
      attribute :definition, Lutaml::Lml::Types::TextType
    end
  end
end
