# frozen_string_literal: true

module Lutaml
  module Lml
    class OperationParameter < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :type, :string
      attribute :direction, :string, default: "in"
      attribute :default, :string
    end
  end
end
