# frozen_string_literal: true

# lib/lutaml/model/xml/decisions/element_prefix_resolver.rb
require_relative 'decision_engine'
require_relative 'decision_context'

module Lutaml
  module Model
    module Xml
      module Decisions
        # Element Prefix Resolver - Determines element namespace format
        #
        # This is the main public API for element namespace decisions.
        # Replaces the procedural determine_element_prefix method.
        class ElementPrefixResolver
          attr_reader :engine

          def initialize(engine = DecisionEngine.default)
            @engine = engine
            freeze
          end

          # Resolve the prefix decision for an element
          #
          # @param xml_element [XmlDataModel::XmlElement] The element
          # @param mapping [Xml::Mapping] The mapping
          # @param needs [NamespaceNeeds] Namespace needs
          # @param options [Hash] Serialization options
          # @param is_root [Boolean] Whether this is the root element
          # @param parent_format [Symbol, nil] Parent's format (:prefix or :default)
          # @param parent_namespace_class [Class, nil] Parent's namespace class
          # @param parent_hoisted [Hash] Namespaces hoisted on parent {prefix => uri}
          # @return [String, nil] The prefix to use, or nil for default format
          def resolve(xml_element, mapping, needs, options,
                     is_root: false,
                     parent_format: nil,
                     parent_namespace_class: nil,
                     parent_hoisted: {})

            # Create decision context
            context = DecisionContext.new(
              element: xml_element,
              mapping: mapping,
              needs: needs,
              options: options,
              is_root: is_root,
              parent_format: parent_format,
              parent_namespace_class: parent_namespace_class,
              parent_hoisted: parent_hoisted
            )

            # Execute decision engine
            decision = @engine.execute(context)

            # Return prefix (or nil for default format)
            decision.prefix
          end

          # Resolve with full decision details (for debugging/logging)
          #
          # @return [Decision] The full decision object
          def resolve_with_decision(xml_element, mapping, needs, options,
                                   is_root: false,
                                   parent_format: nil,
                                   parent_namespace_class: nil,
                                   parent_hoisted: {})

            context = DecisionContext.new(
              element: xml_element,
              mapping: mapping,
              needs: needs,
              options: options,
              is_root: is_root,
              parent_format: parent_format,
              parent_namespace_class: parent_namespace_class,
              parent_hoisted: parent_hoisted
            )

            @engine.execute(context)
          end
        end
      end
    end
  end
end
