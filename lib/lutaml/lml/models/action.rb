# frozen_string_literal: true

module Lutaml
  module Lml
    class Action < Lutaml::Model::Serializable
      attribute :verb, :string
      attribute :direction, :string
    end
  end
end
