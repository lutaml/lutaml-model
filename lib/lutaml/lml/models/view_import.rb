# frozen_string_literal: true

require "lutaml/model"

module Lutaml
  module Lml
    class ViewImport < Lutaml::Model::Serializable
      attribute :path, :string
    end
  end
end
