# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Handles polymorphic value detection for XML adapters
      #
      # This module provides a shared method to determine if a value should be
      # treated as polymorphic during serialization. Polymorphism is detected
      # through two mechanisms:
      #
      # 1. Explicit declaration: The attribute has `polymorphic: true` option
      # 2. Implicit hierarchy: The value's class has an attribute with
      #    `polymorphic_class: true`, indicating it's part of a polymorphic
      #    inheritance tree
      #
      # This logic is identical across all XML adapters (Nokogiri, Oga, Ox)
      # and has been extracted here to maintain DRY principles.
      module PolymorphicValueHandler
        # Determine if a value should be treated as polymorphic
        #
        # @param attribute [Lutaml::Model::Attribute] the attribute definition
        # @param value [Object] the value to check
        # @return [Boolean] true if value should use polymorphic serialization
        def polymorphic_value?(attribute, value)
          return false unless attribute
          return false unless value.respond_to?(:class)

          # Check if attribute explicitly declares polymorphism
          return true if attribute.options[:polymorphic] || attribute.polymorphic?

          # Check if value's class is part of a polymorphic hierarchy
          # (has an attribute with polymorphic_class: true)
          value_class = value.class
          return false unless value_class.respond_to?(:attributes)

          value_class.attributes.values.any?(&:polymorphic?)
        end
      end
    end
  end
end