# frozen_string_literal: true

module Lutaml
  module Lml
    class Fidelity < Lutaml::Model::Serializable
      attribute :hideMembers, :boolean
      attribute :hideOtherClasses, :boolean
    end
  end
end
