# frozen_string_literal: true

module Lutaml
  module Lml
    class Collection < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :includes, :string, collection: true
      attribute :validations, :string, collection: true
    end
  end
end