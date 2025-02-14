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

module Lutaml
  module Model
    # Error for passing incorrect model type
    #
    # @api private
    class IncorrectModelError < StandardError
    end

    class BaseModel < Serializable
    end

    def self.registered_class(class_alias)
      @register[class_alias]
    end

    def self.register_class(class_alias, class_name)
      @register ||= {}
      @register[class_alias] = class_name
    end
  end
end
