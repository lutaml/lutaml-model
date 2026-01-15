# frozen_string_literal: true

require_relative '../../config'
require_relative 'reference'

module Lutaml
  module Model
    module Xml
      module TypeNamespace
        # Collects type namespace references from a model
        #
        # Type namespaces are namespaces declared on attribute types via
        # xml_namespace directive. They are collected separately from element
        # namespaces because they have different scoping rules.
        class Collector
          attr_reader :register

          def initialize(register = nil)
            @register = register || Lutaml::Model::Config.default_register
          end

          # Collect type namespace references from a single attribute
          #
          # @param attribute [Attribute] The attribute definition
          # @param rule [MappingRule] The mapping rule
          # @param context [Symbol] :attribute or :element
          # @return [Reference, nil] The type namespace reference, or nil
          def collect_from_attribute(attribute, rule, context)
            return nil if rule.namespace_set?
            return nil unless attribute

            # Create reference (lazy resolution of actual namespace)
            Reference.new(attribute, rule, context)
          end

          # Collect all type namespace references from a mapping
          #
          # @param mapping [Xml::Mapping] The XML mapping
          # @param mapper_class [Class] The model class
          # @return [Array<Reference>] Array of type namespace references
          def collect_from_mapping(mapping, mapper_class)
            references = []

            return references unless mapper_class&.respond_to?(:attributes)

            attributes = mapper_class.attributes

            # Collect from attribute rules
            mapping.attributes.each do |attr_rule|
              next unless attr_rule.attribute?
              next if attr_rule.to.nil?

              attr_def = attributes[attr_rule.to]
              next unless attr_def

              # Only collect if rule doesn't explicitly set namespace
              next if attr_rule.namespace_set?

              ref = collect_from_attribute(attr_def, attr_rule, :attribute)
              references << ref if ref
            end

            # Collect from element rules
            mapping.elements.each do |elem_rule|
              attr_def = attributes[elem_rule.to]
              next unless attr_def

              # Only collect if rule doesn't explicitly set namespace
              next if elem_rule.namespace_set?

              ref = collect_from_attribute(attr_def, elem_rule, :element)
              references << ref if ref
            end

            references
          end

          # Resolve type namespace references to namespace classes
          #
          # @param references [Array<Reference>] The type namespace references
          # @return [Hash<Symbol, Class>] Hash of context => Set of namespace classes
          def resolve_references(references)
            result = {
              attributes: Set.new,
              elements: Set.new,
            }

            references.each do |ref|
              ns_class = ref.namespace_class(@register)
              next unless ns_class

              if ref.attribute_context?
                result[:attributes] << ns_class
              else
                result[:elements] << ns_class
              end
            end

            result
          end
        end
      end
    end
  end
end
