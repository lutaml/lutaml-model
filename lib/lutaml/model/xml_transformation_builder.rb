# frozen_string_literal: true

require_relative "transformation_builder"
require_relative "xml/transformation"

module Lutaml
  module Model
    # Builder for XML format transformations.
    #
    # Creates Xml::Transformation instances for serializing models to XML.
    #
    # @example Usage
    #   builder = XmlTransformationBuilder
    #   transformation = builder.build(Person, mapping, :xml, register)
    class XmlTransformationBuilder < TransformationBuilder
      # Formats handled by this builder
      FORMATS = [:xml].freeze

      # Build an XML transformation instance.
      #
      # @param model_class [Class] The model class
      # @param mapping [Xml::Mapping] The XML mapping
      # @param format [Symbol] The format (:xml)
      # @param register [Register, nil] The register for type resolution
      # @return [Xml::Transformation] The XML transformation instance
      def self.build(model_class, mapping, format, register)
        Xml::Transformation.new(model_class, mapping, format, register)
      end
    end
  end
end
