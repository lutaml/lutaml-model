# frozen_string_literal: true

require "moxml"
require_relative "model/uninitialized_class"
require_relative "model/errors"
require_relative "model/services"
require_relative "model/version"
require_relative "model/type"
require_relative "model/type_registry"
require_relative "model/type_substitution"
require_relative "model/type_context"
require_relative "model/type_resolver"
require_relative "model/cached_type_resolver"
require_relative "model/context_registry"
require_relative "model/import_registry"
require_relative "model/global_context"
require_relative "model/utils"
require_relative "model/serializable"
require_relative "model/error"
require_relative "model/constants"
require_relative "model/config"
require_relative "model/configuration"
require_relative "model/instrumentation"
require_relative "model/global_register"
require_relative "model/register"
require_relative "model/transformation"
require_relative "model/compiled_rule"
require_relative "xml/data_model"
require_relative "model/format_registry"
require_relative "model/collection"
require_relative "xml"
require_relative "key_value"
require_relative "model/json"
require_relative "model/yaml"
require_relative "model/toml"
require_relative "model/hash"
require_relative "model/jsonl"
require_relative "model/yamls"
require_relative "model/store"
require_relative "model/type/reference"
require_relative "model/schema"

module Lutaml
  module Model
    # Error for passing incorrect model type
    #
    # @api private
    class IncorrectModelError < StandardError
    end

    class BaseModel < Serializable
    end

    # Module-level configuration
    #
    # @example
    #   Lutaml::Model.configure do |config|
    #     config.xml_adapter = :nokogiri
    #     config.json_adapter = :oj
    #   end
    #
    # @yield [Configuration] the configuration object
    # @return [Configuration] the configuration object
    def self.configure
      @configuration ||= Configuration.new
      yield @configuration if block_given?
      @configuration
    end

    # Get the current configuration
    #
    # @return [Configuration] the current configuration
    def self.configuration
      @configuration ||= Configuration.new
    end

    # Reset configuration to defaults
    #
    # @return [void]
    def self.reset_configuration!
      @configuration = nil
    end
  end
end
