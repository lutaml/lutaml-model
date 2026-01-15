# frozen_string_literal: true

require_relative 'collector'
require_relative 'resolver'
require_relative 'declaration'

module Lutaml
  module Model
    module Xml
      module TypeNamespace
        # Plans type namespace declarations for elements
        #
        # Type namespaces are declared on PARENT elements and used by
        # CHILD elements as prefixes. This planner determines where
        # to declare each type namespace.
        class Planner
          attr_reader :collector, :resolver

          def initialize(register = nil)
            @collector = Collector.new(register)
            @resolver = Resolver.new
          end

          # Plan type namespace declarations for an element
          #
          # @param mapping [Xml::Mapping] The XML mapping
          # @param mapper_class [Class] The model class
          # @param element_namespace_class [XmlNamespace, nil] Element's namespace
          # @param existing_declarations [Hash] Already declared namespaces {prefix => uri}
          # @return [Array<Declaration>] Array of type namespace declarations
          def plan_for_element(mapping, mapper_class, element_namespace_class, existing_declarations = {})
            # Collect type namespace references
            references = @collector.collect_from_mapping(mapping, mapper_class)

            # Resolve to namespace classes
            resolved = @collector.resolve_references(references)

            # Build declarations
            declarations = []

            # Process attribute type namespaces
            resolved[:attributes].each do |ns_class|
              next if already_declared?(ns_class, existing_declarations)
              next unless @resolver.needs_declaration?(ns_class, element_namespace_class)

              prefix = ns_class.prefix_default || generate_prefix("attr", existing_declarations)

              declarations << Declaration.new(
                namespace_class: ns_class,
                prefix: prefix,
                declared_at: :parent,
                element_name: mapping&.root_element
              )
            end

            # Process element type namespaces
            resolved[:elements].each do |ns_class|
              next if already_declared?(ns_class, existing_declarations)
              next unless @resolver.needs_declaration?(ns_class, element_namespace_class)

              prefix = ns_class.prefix_default || generate_prefix("elem", existing_declarations)

              declarations << Declaration.new(
                namespace_class: ns_class,
                prefix: prefix,
                declared_at: :parent,
                element_name: mapping&.root_element
              )
            end

            declarations
          end

          # Plan type namespace declarations for root element
          #
          # @param mapping [Xml::Mapping] The XML mapping
          # @param mapper_class [Class] The model class
          # @param element_namespace_class [XmlNamespace, nil] Root's namespace
          # @return [Array<Declaration>] Array of type namespace declarations
          def plan_for_root(mapping, mapper_class, element_namespace_class)
            plan_for_element(mapping, mapper_class, element_namespace_class).map do |decl|
              # Convert to root-level declarations
              Declaration.new(
                namespace_class: decl.namespace_class,
                prefix: decl.prefix,
                declared_at: :root,
                element_name: decl.element_name
              )
            end
          end

          private

          # Check if namespace is already declared
          #
          # @param ns_class [XmlNamespace] The namespace class
          # @param existing [Hash] Existing declarations {prefix => uri}
          # @return [Boolean] true if already declared
          def already_declared?(ns_class, existing)
            existing.value?(ns_class.uri)
          end

          # Generate a unique prefix
          #
          # @param base [String] Base prefix (e.g., "attr", "elem")
          # @param existing [Hash] Existing declarations {prefix => uri}
          # @return [String] A unique prefix
          def generate_prefix(base, existing)
            counter = 0
            loop do
              prefix = counter == 0 ? "tn#{base}" : "tn#{base}#{counter}"
              return prefix unless existing.key?(prefix)
              counter += 1
            end
          end
        end
      end
    end
  end
end
