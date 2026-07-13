# frozen_string_literal: true

require "uri"

module Lutaml
  module Model
    module Schema
      # Derives the class name and default prefix for a generated
      # XmlNamespace subclass from a namespace URI.
      #
      # Used by both XSD and RNG compilers so the same URI always
      # produces the same class name across formats.
      module NamespaceNaming
        module_function

        def prefix_for(uri)
          case uri
          when %r{/math$}    then "m"
          when %r{XMLSchema} then "xs"
          when %r{/(\w+)\z}  then ::Regexp.last_match(1)[0..2]
          else "ns"
          end
        end

        def class_name_for(uri)
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
