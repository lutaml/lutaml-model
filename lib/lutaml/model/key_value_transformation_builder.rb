# frozen_string_literal: true

require_relative "transformation_builder"
require_relative "key_value/transformation"

module Lutaml
  module Model
    # Builder for key-value format transformations (JSON, YAML, TOML, Hash).
    #
    # Creates KeyValue::Transformation instances for serializing models to
    # key-value formats outputs.
    #
    # @example Usage
    #   builder = KeyValueTransformationBuilder
    #   transformation = builder.build(Person, mapping, :json, register)
    class KeyValueTransformationBuilder < TransformationBuilder
      # Formats handled by this builder
      FORMATS = %i[json yaml toml hash].freeze

      # Build a KeyValue transformation instance.
      #
      # @param model_class [Class] The model class
      # @param mapping [KeyValue::Mapping] The key-value mapping
      # @param format [Symbol] The format (:json, :yaml, :toml, :hash)
      # @param register [Register, nil] The register for type resolution
      # @return [KeyValue::Transformation] The KeyValue transformation instance
      def self.build(model_class, mapping, format, register)
        KeyValue::Transformation.new(model_class, mapping, format, register)
      end
    end
  end
end
