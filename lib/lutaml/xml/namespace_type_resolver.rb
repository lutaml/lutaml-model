# frozen_string_literal: true

module Lutaml
  module Xml
    # Namespace-aware wrapper for TypeResolver
    #
    # This class provides namespace-aware type resolution WITHOUT modifying
    # the stateless TypeResolver design. It acts as a wrapper that adds
    # namespace context to type resolution.
    #
    # @example Basic usage
    #   resolver = NamespaceTypeResolver.new(context)
    #   type = resolver.resolve_type(:string, namespace: MyNamespace)
    #
    # @example Resolve types by namespace URI
    #   types = NamespaceTypeResolver.resolve_by_namespace_uri(
    #     "http://example.com/ns",
    #     context
    #   )
    #
    class NamespaceTypeResolver
      # @return [Object] the context for type resolution
      attr_reader :context

      # Create a new NamespaceTypeResolver
      #
      # @param context [Object] the context for type resolution
      def initialize(context)
        @context = context
      end

      # Resolve a type with optional namespace validation
      #
      # @param name [Symbol, String] the type name to resolve
      # @param namespace [Class, nil] optional namespace class to validate against
      # @return [Class, nil] the resolved type class
      # @raise [NamespaceMismatchError] if namespace doesn't match type's namespace
      #
      # @example Resolve without namespace check
      #   resolver.resolve_type(:string)
      #
      # @example Resolve with namespace validation
      #   resolver.resolve_type(:string, namespace: MyNamespace)
      def resolve_type(name, namespace: nil)
        type = Lutaml::Model::TypeResolver.resolve(name, context)
        return type unless namespace
        return type unless type

        validate_namespace_match!(type, namespace)
        type
      end

      # Resolve all types in a given namespace
      #
      # @param uri [String] the namespace URI to search for
      # @return [Array<Class>] array of type classes in that namespace
      #
      # @example Find all types in a namespace
      #   types = resolver.resolve_types_by_namespace("http://example.com/ns")
      def resolve_types_by_namespace(uri)
        return [] unless context.respond_to?(:registry)

        context.registry.types.select do |_name, type_class|
          next false unless type_class <= Lutaml::Model::Type::Value

          type_ns = type_class.namespace_class
          type_ns&.uri == uri
        end.values
      end

      # Check if a type is in a specific namespace
      #
      # @param type_class [Class] the type class to check
      # @param namespace [Class] the namespace class to check against
      # @return [Boolean] true if type is in the namespace
      def self.type_in_namespace?(type_class, namespace)
        return false unless type_class.is_a?(Class) && type_class <= Lutaml::Model::Type::Value

        type_ns = type_class.namespace_class
        return false unless type_ns

        type_ns == namespace || type_ns.uri == namespace.uri
      end

      # Get the namespace URI for a type
      #
      # @param type_class [Class] the type class
      # @return [String, nil] the namespace URI or nil
      def self.type_namespace_uri(type_class)
        return nil unless type_class.is_a?(Class) && type_class <= Lutaml::Model::Type::Value

        type_ns = type_class.namespace_class
        return nil unless type_ns

        type_ns.respond_to?(:uri) ? type_ns.uri : nil
      end

      private

      # Validate that the type's namespace matches the expected namespace
      #
      # @param type [Class] the resolved type class
      # @param expected_ns [Class] the expected namespace class
      # @raise [NamespaceMismatchError] if namespaces don't match
      def validate_namespace_match!(type, expected_ns)
        return unless type.is_a?(Class) && type <= Lutaml::Model::Type::Value

        type_ns = type.namespace_class

        # Type has no namespace - this is OK, parent will provide
        return unless type_ns

        # Check if namespaces match
        return if namespaces_match?(type_ns, expected_ns)

        raise Error::NamespaceMismatchError.new(type, expected_ns)
      end

      # Check if two namespaces match
      #
      # @param ns1 [Class] first namespace class
      # @param ns2 [Class] second namespace class
      # @return [Boolean] true if namespaces match
      def namespaces_match?(ns1, ns2)
        return true if ns1 == ns2

        # Compare by URI if both have it
        uri1 = ns1.respond_to?(:uri) ? ns1.uri : nil
        uri2 = ns2.respond_to?(:uri) ? ns2.uri : nil

        uri1 && uri2 && uri1 == uri2
      end
    end
  end
end
