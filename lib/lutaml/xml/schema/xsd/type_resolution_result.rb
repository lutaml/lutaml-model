# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Represents the result of resolving a qualified type name
        class TypeResolutionResult < Lutaml::Model::Serializable
          # Whether the type was successfully resolved
          attribute :resolved, :boolean

          # The original qualified name that was searched for
          attribute :qname, :string

          # The resolved namespace URI
          attribute :namespace, :string

          # The local name (type name without prefix/namespace)
          attribute :local_name, :string

          # The resolved type definition (SimpleType, ComplexType, Element, etc.)
          # Note: This is not serialized in YAML as it's a complex object reference
          attr_accessor :definition

          # The source XSD file where the type was found
          attribute :schema_file, :string

          # Steps taken to resolve the type (for debugging/tracing)
          attribute :resolution_path, :string, collection: true

          # Error message if resolution failed
          attribute :error_message, :string

          yaml do
            map "resolved", to: :resolved
            map "qname", to: :qname
            map "namespace", to: :namespace
            map "local_name", to: :local_name
            map "schema_file", to: :schema_file
            map "resolution_path", to: :resolution_path
            map "error_message", to: :error_message
          end

          # Check if the type was successfully resolved
          # @return [Boolean]
          def resolved?
            resolved == true
          end

          # Get the type name from the definition if available
          # @return [String, nil]
          def type_name
            definition&.name
          end

          # Get the type class name if definition is available
          # @return [String, nil]
          def type_class
            definition&.class&.name
          end

          # Create a successful resolution result
          # @param qname [String] The original qualified name
          # @param namespace [String] The resolved namespace URI
          # @param local_name [String] The local type name
          # @param definition [Base] The type definition object
          # @param schema_file [String] The source schema file
          # @param resolution_path [Array<String>] Steps taken to resolve
          # @return [TypeResolutionResult]
          def self.success(qname:, namespace:, local_name:, definition:,
      schema_file:, resolution_path: [])
            result = new(
              resolved: true,
              qname: qname,
              namespace: namespace,
              local_name: local_name,
              schema_file: schema_file,
              resolution_path: resolution_path,
              error_message: nil,
            )
            # Set definition separately since it's attr_accessor, not attribute
            result.definition = definition
            result
          end

          # Create a failed resolution result
          # @param qname [String] The original qualified name
          # @param namespace [String, nil] The attempted namespace URI
          # @param local_name [String, nil] The local type name
          # @param error_message [String] The error message
          # @param resolution_path [Array<String>] Steps taken before failure
          # @return [TypeResolutionResult]
          def self.failure(qname:, error_message:, namespace: nil, local_name: nil,
      resolution_path: [])
            result = new(
              resolved: false,
              qname: qname,
              namespace: namespace,
              local_name: local_name,
              schema_file: nil,
              resolution_path: resolution_path,
              error_message: error_message,
            )
            # Set definition separately since it's attr_accessor, not attribute
            result.definition = nil
            result
          end
        end
      end
    end
  end
end
