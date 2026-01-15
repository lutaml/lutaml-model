# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # Generates XmlNamespace class definitions from XSD namespace URIs
        class XmlNamespaceClass
          attr_accessor :uri, :prefix_default, :class_name

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true

            require "lutaml/model"

            # Namespace: <%= uri %>
            class <%= class_name %> < Lutaml::Model::Xml::W3c::XmlNamespace
              uri <%= uri.inspect %>
              prefix_default <%= prefix_default.inspect %>
            end
          TEMPLATE

          def initialize(uri:, prefix: nil, class_name: nil)
            @uri = uri
            @prefix_default = prefix || derive_prefix_from_uri(uri)
            @class_name = class_name || derive_class_name_from_uri(uri)
          end

          def to_class
            TEMPLATE.result(binding)
          end

          def required_file
            "require_relative \"#{Utils.snake_case(class_name)}\""
          end

          def class_reference
            class_name
          end

          private

          def derive_prefix_from_uri(uri)
            # Extract meaningful part from URI
            # http://schemas.openxmlformats.org/officeDocument/2006/math -> "m"
            # http://www.w3.org/2001/XMLSchema -> "xs"
            case uri
            when %r{/math$}
              "m"
            when %r{XMLSchema}
              "xs"
            when %r{/(\w+)$}
              $1[0..2] # First 3 chars
            else
              "ns" # Generic prefix
            end
          end

          def derive_class_name_from_uri(uri)
            # Extract domain and path components
            # http://schemas.openxmlformats.org/officeDocument/2006/math
            # -> OoxmlMathNamespace
            return "XmlSchemaNamespace" if uri.include?("XMLSchema")

            parts = URI.parse(uri).host&.split(".")&.reject(&:empty?) || []
            path_parts = URI.parse(uri).path&.split("/")&.reject(&:empty?) || []

            # Use reverse domain notation + meaningful path parts
            # Filter out version numbers and empty parts
            name_parts = parts.reverse.take(2) + path_parts.last(2)
            name_parts = name_parts.map { |p| Utils.camel_case(p.gsub(/\d+/, '').gsub(/[^a-zA-Z]/, '')) }
                                   .reject(&:empty?)

            # Fallback if no valid parts
            return "DefaultNamespace" if name_parts.empty?

            name_parts.join + "Namespace"
          rescue URI::InvalidURIError, StandardError
            # Fallback for invalid URIs or any other errors
            "DefaultNamespace"
          end
        end
      end
    end
  end
end
