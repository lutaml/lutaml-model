# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Represents an XML attribute
      class XmlAttribute
        attr_reader :name, :value, :namespace, :namespace_prefix

        def initialize(name, value, namespace: nil, namespace_prefix: nil)
          @name = name
          @value = value
          @namespace = namespace
          @namespace_prefix = namespace_prefix
        end

        def unprefixed_name
          if namespace_prefix
            name.split(":").last
          else
            name
          end
        end

        def namespaced_name
          # For type-namespaced attributes (those with xml_namespace declaration),
          # return the prefixed name (e.g., "xml:lang", "ex:attr")
          # rather than URI:name format (e.g., "http://www.w3.org/XML/1998/namespace:lang")
          if namespace_prefix
            name
          elsif namespace
            "#{namespace}:#{unprefixed_name}"
          else
            unprefixed_name
          end
        end
      end
    end
  end
end
