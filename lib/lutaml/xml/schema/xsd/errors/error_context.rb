# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        module Errors
          # Value object representing contextual information for enhanced errors
          #
          # @example Creating an error context
          #   context = ErrorContext.new(
          #     location: "/root/element[1]",
          #     namespace: "http://example.com",
          #     expected_type: "xs:string",
          #     actual_value: "123"
          #   )
          class ErrorContext
            # @return [String, nil] XPath location of the error
            attr_reader :location

            # @return [String, nil] Namespace URI
            attr_reader :namespace

            # @return [String, nil] Expected type name
            attr_reader :expected_type

            # @return [String, nil] Actual value that caused the error
            attr_reader :actual_value

            # @return [Hash] Additional context attributes
            attr_reader :additional

            # Initialize error context with attributes
            #
            # @param attrs [Hash] Context attributes
            # @option attrs [String] :location XPath location
            # @option attrs [String] :namespace Namespace URI
            # @option attrs [String] :expected_type Expected type name
            # @option attrs [String] :actual_value Actual value
            def initialize(attrs = {})
              @location = attrs[:location]
              @namespace = attrs[:namespace]
              @expected_type = attrs[:expected_type]
              @actual_value = attrs[:actual_value]
              @additional = attrs.except(
                :location, :namespace, :expected_type,
                :actual_value
              )
            end

            # Convert context to hash representation
            #
            # @return [Hash] Context as hash
            def to_h
              {
                location: @location,
                namespace: @namespace,
                expected_type: @expected_type,
                actual_value: @actual_value,
              }.merge(@additional).compact
            end
          end
        end
      end
    end
  end
end
