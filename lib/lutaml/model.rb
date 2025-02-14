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

    def self.registry
      @registry ||= {}
    end

    def self.register(class_alias, klass)
      registry[class_alias] = klass
    end

    def self.lookup(class_alias)
      registry[class_alias]
    end

    def self.class_registered?(class_alias)
      registry.key?(class_alias)
    end
  end
end
