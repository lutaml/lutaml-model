# frozen_string_literal: true

require "uri"

module Lutaml
  module Model
    module Schema
      # Base class for any renderer that emits a Lutaml::Xml::W3c::XmlNamespace
      # subclass. Inherited by:
      #   - Lutaml::Model::Schema::XmlCompiler::XmlNamespaceClass
      #   - Lutaml::Model::Schema::RngCompiler::Namespace
      class NamespaceRenderer
        include ClassBoilerplate

        attr_accessor :uri, :prefix_default, :class_name

        def initialize(uri:, prefix: nil, class_name: nil)
          @uri = uri
          @prefix_default = prefix || derive_prefix_from_uri(uri)
          @class_name = class_name || derive_class_name_from_uri(uri)
          @module_namespace = nil
        end

        # Full render flow. Children may override the entry-point name.
        def to_class(options: {})
          @module_namespace = options[:module_namespace]
          @modules = @module_namespace&.split("::") || []
          Templates::XML_NAMESPACE.result(binding)
        end

        def required_file
          %(require_relative "#{Utils.snake_case(class_name)}")
        end

        def class_reference
          class_name
        end

        # ----------------------------------------------------------------
        # URI heuristics — children may override individual cases.
        # ----------------------------------------------------------------

        def derive_prefix_from_uri(uri)
          case uri
          when %r{/math$}    then "m"
          when %r{XMLSchema} then "xs"
          when %r{/(\w+)\z}  then ::Regexp.last_match(1)[0..2]
          else "ns"
          end
        end

        def derive_class_name_from_uri(uri)
          return "XmlSchemaNamespace" if uri.include?("XMLSchema")

          parsed = URI.parse(uri)
          host_parts = (parsed.host&.split(".") || []).reject(&:empty?)
          path_parts = (parsed.path&.split("/") || []).reject(&:empty?)

          name_parts = host_parts.reverse.take(2) + path_parts.last(2)
          name_parts = name_parts.map do |p|
            Utils.camel_case(p.gsub(/\d+/, "").gsub(/[^a-zA-Z]/, ""))
          end.reject(&:empty?)

          return "DefaultNamespace" if name_parts.empty?

          "#{name_parts.join}Namespace"
        rescue URI::InvalidURIError
          "DefaultNamespace"
        end
      end
    end
  end
end
