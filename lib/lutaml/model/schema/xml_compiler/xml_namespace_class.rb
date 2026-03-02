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

            <%= module_opening -%>
            # Namespace: <%= uri %>
            class <%= class_name %> < Lutaml::Xml::W3c::XmlNamespace
              uri <%= uri.inspect %>
              prefix_default <%= prefix_default.inspect %>
            end
            <%= module_closing -%>
          TEMPLATE

          def initialize(uri:, prefix: nil, class_name: nil)
            @uri = uri
            @prefix_default = prefix || derive_prefix_from_uri(uri)
            @class_name = class_name || derive_class_name_from_uri(uri)
            @module_namespace = nil
          end

          def to_class(options: {})
            @module_namespace = options[:module_namespace]
            @modules = @module_namespace&.split("::") || []
            TEMPLATE.result(binding)
          end

          def required_file
            "require_relative \"#{Utils.snake_case(class_name)}\""
          end

          def class_reference
            class_name
          end

          private

          def module_opening
            return "" if @modules.empty?

            @modules.map.with_index do |mod, i|
              "#{'  ' * i}module #{mod}"
            end.join("\n") + "\n"
          end

          def module_closing
            return "" if @modules.empty?

            @modules.reverse.map.with_index do |_mod, i|
              "#{'  ' * (@modules.size - i - 1)}end"
            end.join("\n")
          end

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

            parsed_uri = URI.parse(uri)
            parts = parsed_uri.host&.split(".")&.reject(&:empty?) || []
            path_parts = parsed_uri.path&.split("/")&.reject(&:empty?) || []

            # Use reverse domain notation + meaningful path parts
            # Filter out version numbers and empty parts
            name_parts = parts.reverse.take(2) + path_parts.last(2)
            name_parts = name_parts.map do |p|
              Utils.camel_case(p.gsub(/\d+/, "").gsub(/[^a-zA-Z]/, ""))
            end
              .reject(&:empty?)

            # Fallback if no valid parts
            return "DefaultNamespace" if name_parts.empty?

            "#{name_parts.join}Namespace"
          rescue URI::InvalidURIError, StandardError
            # Fallback for invalid URIs or any other errors
            "DefaultNamespace"
          end
        end
      end
    end
  end
end
