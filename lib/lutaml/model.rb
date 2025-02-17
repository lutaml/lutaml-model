# frozen_string_literal: true

require "moxml"
require_relative "model/version"
require_relative "model/loggable"
require_relative "model/type"
require_relative "model/utils"
require_relative "model/serializable"
require_relative "model/json_adapter/standard_json_adapter"
require_relative "model/yaml_adapter/standard_yaml_adapter"
require_relative "model/xml_adapter"
require_relative "model/toml_adapter"
require_relative "model/error"
require_relative "model/constants"
require_relative "model/collection"


module Lutaml
  module Model
    # Error for passing incorrect model type
    #
    # @api private
    class IncorrectModelError < StandardError
    end

    class BaseModel < Serializable
    end
  end
end

class Ceramic < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :value, :float
end

class CuratedCollection < Lutaml::Model::Collection
  attribute :curator, :string
  attribute :acquisition_date, :date
  instances :items, Ceramic

  xml do
    root "curated-group"
    map_attribute "curator", to: :curator
    map_element "acquisition-date", to: :acquisition_date
    map_element "artifact", to: :items
  end
end

class TestCollection < Lutaml::Model::Serializable
  attribute :curated_group, Ceramic, collection: CuratedCollection

  xml do
    map_element "curated-group", to: :curated_group
  end
end