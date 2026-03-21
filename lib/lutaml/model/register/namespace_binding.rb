# frozen_string_literal: true

module Lutaml
  module Model
    # Represents a binding between a register and a namespace.
    #
    # This enables version-aware type resolution where different
    # namespaces can map to different type implementations.
    #
    # @example
    #   binding = NamespaceBinding.new(
    #     register_id: :xmi_20131001,
    #     namespace_class: Xmi::Namespace::Omg::Xmi20131001
    #   )
    #
    #   binding.register_id   # => :xmi_20131001
    #   binding.namespace_uri # => "http://www.omg.org/spec/XMI/20131001"
    #
    class NamespaceBinding
      # @api public
      # @return [Symbol] The register ID
      attr_reader :register_id

      # @api public
      # @return [Class] The namespace class
      attr_reader :namespace_class

      # @api public
      # @return [String] The namespace URI
      attr_reader :namespace_uri

      # @api public
      # Create a new namespace binding.
      #
      # @param register_id [Symbol] The register ID
      # @param namespace_class [Class] A Lutaml::Xml::Namespace subclass
      # @raise [ArgumentError] If namespace_class is not a Lutaml::Xml::Namespace
      def initialize(register_id:, namespace_class:)
        validate_namespace_class!(namespace_class)

        @register_id = register_id.to_sym
        @namespace_class = namespace_class
        @namespace_uri = namespace_class.uri
        freeze
      end

      # @api public
      # Check equality with another NamespaceBinding.
      #
      # @param other [Object] Object to compare
      # @return [Boolean] true if equal
      def ==(other)
        return false unless other.is_a?(NamespaceBinding)

        register_id == other.register_id && namespace_uri == other.namespace_uri
      end

      alias eql? ==

      # @api public
      # Hash code for use as hash key.
      #
      # @return [Integer] Hash code
      def hash
        [register_id, namespace_uri].hash
      end

      # @api public
      # Human-readable representation.
      #
      # @return [String] String representation
      def to_s
        "#<#{self.class.name} register=#{register_id} namespace=#{namespace_uri}>"
      end

      alias inspect to_s

      private

      def validate_namespace_class!(namespace_class)
        # Check if Lutaml::Xml::Namespace is defined
        return unless defined?(Lutaml::Xml::Namespace)

        unless namespace_class.is_a?(Class) &&
            namespace_class <= Lutaml::Xml::Namespace
          raise ArgumentError,
                "Expected Lutaml::Xml::Namespace subclass, got #{namespace_class.inspect}"
        end
      end
    end
  end
end
