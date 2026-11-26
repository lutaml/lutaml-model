# frozen_string_literal: true

require "lutaml/model"

module Lutaml
  module Lml
    class ViewFilter < Lutaml::Model::Serializable
      attribute :entity_names, :string, collection: true
    end
  end
end
