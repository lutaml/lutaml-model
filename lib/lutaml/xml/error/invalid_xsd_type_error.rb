# frozen_string_literal: true

module Lutaml
  module Xml
    module Error
      # Raised when an invalid XSD type is specified
      #
      # This error is raised when a type name cannot be resolved to a
      # valid XSD type or custom Type::Value class.
      #
      # @example
      #   raise InvalidXsdTypeError.new("UnknownType", context: MyClass)
      class InvalidXsdTypeError < XmlError
        # @return [String] the invalid type name
        attr_reader :type_name

        # @return [Class, nil] the context class where the error occurred
        attr_reader :context

        # Create a new InvalidXsdTypeError
        #
        # @param type_name [String] the invalid type name
        # @param context [Class, nil] the context class
        # @param message [String, nil] custom error message
        def initialize(type_name, context: nil, message: nil)
          @type_name = type_name
          @context = context

          super(message || default_message)
        end

        private

        def default_message
          msg = "Invalid XSD type: '#{@type_name}'"
          msg += " in #{@context}" if @context
          msg += ". Custom types must be defined as Lutaml::Model::Type::Value subclasses."
          msg
        end
      end
    end
  end
end
