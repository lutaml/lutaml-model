# frozen_string_literal: true

require_relative "../model/transformation_builder"
require_relative "transformation"

module Lutaml
  module Xml
    # Builder for XML format transformations.
    #
    # Creates Transformation instances for serializing models to XML.
    #
    # @example Usage
    #   builder = TransformationBuilder
    #   transformation = builder.build(Person, mapping, :xml, register)
    class TransformationBuilder < ::Lutaml::Model::TransformationBuilder
      # Formats handled by this builder
      FORMATS = [:xml].freeze

      # Build an XML transformation instance.
      #
      # @param model_class [Class] The model class
      # @param mapping [Mapping] The XML mapping
      # @param format [Symbol] The format (:xml)
      # @param register [Register, nil] The register for type resolution
      # @return [Transformation] The XML transformation instance
      def self.build(model_class, mapping, format, register)
        Transformation.new(model_class, mapping, format, register)
      end
    end
  end
end
