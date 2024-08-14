require_relative "xml_attribute"

module Lutaml
  module Model
    module XmlAdapter
      class XmlElement
        attr_reader :attributes,
                    :children,
                    :text,
                    :namespace_prefix,
                    :parent_document

        def initialize(
          name,
          attributes = {},
          children = [],
          text = nil,
          parent_document: nil,
          namespace_prefix: nil
        )
          @name = extract_name(name)
          @namespace_prefix = namespace_prefix || extract_namespace_prefix(name)
          @attributes = attributes # .map { |k, v| XmlAttribute.new(k, v) }
          @children = children
          @text = text
          @parent_document = parent_document
        end

        def name
          if namespace_prefix
            "#{namespace_prefix}:#{@name}"
          else
            @name
          end
        end

        def unprefixed_name
          @name
        end

        def document
          XmlDocument.new(self)
        end

        def namespaces
          @namespaces || @parent_document&.namespaces || {}
        end

        def own_namespaces
          @namespaces || {}
        end

        def namespace
          return default_namespace unless namespace_prefix

          namespaces[namespace_prefix]
        end

        def attribute_is_namespace?(name)
          name.to_s.start_with?("xmlns")
        end

        def add_namespace(namespace)
          @namespaces ||= {}
          @namespaces[namespace.prefix] = namespace
        end

        def default_namespace
          namespaces[nil] || @parent_document&.namespaces&.dig(nil)
        end

        def extract_name(name)
          n = name.to_s.split(":")
          return name if n.length <= 1

          n[1..].join(":")
        end

        def extract_namespace_prefix(name)
          n = name.to_s.split(":")
          return if n.length <= 1

          n.first
        end

        def order
          children.each_with_object([]) do |child, arr|
            arr << child.unprefixed_name
          end
        end
      end
    end
  end
end
