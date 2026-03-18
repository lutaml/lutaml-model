# frozen_string_literal: true

module Lutaml
  module Xml
    module Error
      # Raised when an invalid namespace class is provided
      #
      # This error is raised when a namespace parameter is not a valid
      # XmlNamespace class, :blank, or :inherit symbol.
      #
      # @example
      #   raise InvalidNamespaceError.new(expected: "XmlNamespace class", got: String)
      class InvalidNamespaceError < XmlError
        # @return [String] the expected namespace type
        attr_reader :expected

        # @return [Object] the actual value received
        attr_reader :received

        # Create a new InvalidNamespaceError
        #
        # @param expected [String] description of expected value
        # @param got [Object] the actual value received
        # @param message [String, nil] custom error message
        def initialize(expected: nil, got: nil, message: nil)
          @expected = expected
          @received = got

          super(message || default_message)
        end

        private

        def default_message
          if expected && received
            "Expected #{expected}, got #{received.class}: #{received.inspect}"
          elsif received
            "Invalid namespace: #{received.class} is not a valid XmlNamespace class"
          else
            "Invalid namespace provided"
          end
        end
      end
    end
  end
end
