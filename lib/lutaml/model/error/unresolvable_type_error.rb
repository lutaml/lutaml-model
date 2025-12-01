module Lutaml
  module Model
    # Error raised when an XSD type reference cannot be resolved
    #
    # This error occurs during XSD generation when:
    # - A custom xsd_type value is used but the type is not defined
    # - A type reference cannot be found in the model hierarchy
    # - A type is neither a W3C built-in nor a custom LutaML type
    #
    # @example
    #   class MyType < Lutaml::Model::Type::String
    #     def self.xsd_type
    #       "UndefinedType"  # Not xs: prefixed, not defined anywhere
    #     end
    #   end
    #
    #   # Will raise UnresolvableTypeError during XSD generation
    class UnresolvableTypeError < Error
      # Initialize the error with a descriptive message
      #
      # @param message [String] The error message describing the unresolvable type
      def initialize(message = "XSD type cannot be resolved")
        super(message)
      end
    end
  end
end
