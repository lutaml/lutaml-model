# frozen_string_literal: true

require_relative "validation_error"
require_relative "validation_result"

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Namespace URI remapping rule (URI → URI transformation)
        class NamespaceUriRemapping < Lutaml::Model::Serializable
          attribute :from_uri, :string
          attribute :to_uri, :string

          yaml do
            map "from_uri", to: :from_uri
            map "to_uri", to: :to_uri
          end

          # Validate remapping
          # @return [ValidationResult]
          def validate
            errors = []

            from_missing = from_uri.nil? || from_uri.empty?
            to_missing = to_uri.nil? || to_uri.empty?

            if from_missing
              errors << ValidationError.create(
                field: :from_uri,
                message: "Source URI is required",
                constraint: "presence",
              )
            end

            if to_missing
              errors << ValidationError.create(
                field: :to_uri,
                message: "Target URI is required",
                constraint: "presence",
              )
            end

            # Only check equality if both URIs are present
            if !from_missing && !to_missing && from_uri == to_uri
              errors << ValidationError.create(
                field: :to_uri,
                message: "Target URI must be different from source URI",
                value: to_uri,
                constraint: "!= from_uri",
              )
            end

            errors.empty? ? ValidationResult.success : ValidationResult.failure(errors)
          end

          # Check if remapping is valid
          # @return [Boolean]
          def valid?
            validate.valid?
          end

          # Raise error if invalid
          # @raise [ValidationFailedError]
          def validate!
            validate.validate!
          end

          # Apply remapping to a URI
          # @param uri [String] Namespace URI
          # @return [String] Remapped URI or original
          def apply(uri)
            uri == from_uri ? to_uri : uri
          end
        end
      end
    end
  end
end
