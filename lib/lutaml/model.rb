# frozen_string_literal: true

require "moxml"
require_relative "model/uninitialized_class"
require_relative "model/errors"
require_relative "model/services"
require_relative "model/version"
require_relative "model/type"
require_relative "model/utils"
require_relative "model/serializable"
require_relative "model/xml_adapter"
require_relative "model/error"
require_relative "model/constants"
require_relative "model/config"
require_relative "model/format_registry"
require_relative "model/collection"
require_relative "model/key_value_document"
require_relative "model/yaml"
require_relative "model/json"
require_relative "model/toml"
require_relative "model/hash"
require_relative "model/xml"

module Lutaml
  module Model
    # Error for passing incorrect model type
    #
    # @api private
    class IncorrectModelError < StandardError
    end

    class BaseModel < Serializable
    end

    # Register default adapters
    # Lutaml::Model::FormatRegistry.register(
    #   :json,
    #   mapping_class: KeyValueMapping,
    #   adapter_class: JsonAdapter::StandardJsonAdapter,
    #   transformer: Lutaml::Model::KeyValueTransform,
    # )

    # Lutaml::Model::FormatRegistry.register(
    #   :yaml,
    #   mapping_class: KeyValueMapping,
    #   adapter_class: YamlAdapter::StandardYamlAdapter,
    #   transformer: Lutaml::Model::KeyValueTransform,
    # )

    # Lutaml::Model::FormatRegistry.register(
    #   :toml,
    #   mapping_class: KeyValueMapping,
    #   adapter_class: nil,
    #   transformer: Lutaml::Model::KeyValueTransform,
    # )

    # Lutaml::Model::FormatRegistry.register(
    #   :xml,
    #   mapping_class: XmlMapping,
    #   adapter_class: nil,
    #   transformer: Lutaml::Model::XmlTransform,
    # )
  end
end
