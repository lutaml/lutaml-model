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

class Title < Lutaml::Model::Serializable
end

class TitleCollection < Lutaml::Model::Collection
  instances :abc, Title

  xml do
    root "title-group"
    map_element "artifact", to: :items
  end
end

class BibItem < Lutaml::Model::Serializable
  attribute :title, TitleCollection

  xml do
    root "bibitem"
    map_element "title", to: :title
  end
end

