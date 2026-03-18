# frozen_string_literal: true

module Lutaml
  module Xml
    module Error
      # Raised when a namespace mismatch occurs during type resolution
      #
      # This error is raised when attempting to resolve a type in a specific
      # namespace, but the type's configured namespace doesn't match.
      #
      # @example
      #   raise NamespaceMismatchError.new(MyType, OtherNamespace)
      class NamespaceMismatchError < XmlError
        # @return [Class] the type class being resolved
        attr_reader :type_class

        # @return [Class] the expected namespace class
        attr_reader :expected_namespace

        # @return [Class, nil] the actual namespace class configured on the type
        attr_reader :actual_namespace

        # Create a new NamespaceMismatchError
        #
        # @param type_class [Class] the type class being resolved
        # @param expected_namespace [Class] the expected namespace class
        # @param message [String, nil] custom error message
        def initialize(type_class, expected_namespace, message: nil)
          @type_class = type_class
          @expected_namespace = expected_namespace
          @actual_namespace = if type_class.is_a?(Class) && type_class <= Lutaml::Model::Type::Value
                                type_class.namespace_class
                              end

          super(message || default_message)
        end

        private

        def default_message
          msg = "Namespace mismatch for type #{@type_class.name}: "
          msg += "expected namespace #{@expected_namespace.uri}"
          msg += if @actual_namespace
                   ", but type is configured with namespace #{@actual_namespace.uri}"
                 else
                   ", but type has no namespace configured"
                 end
          msg
        end
      end
    end
  end
end
