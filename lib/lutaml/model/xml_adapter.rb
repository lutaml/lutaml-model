# lib/lutaml/model/xml_adapter.rb

module Lutaml
  module Model
    module XmlAdapter
      class Document
        attr_reader :root

        def initialize(root)
          @root = root
        end

        def self.parse(xml)
          raise NotImplementedError, "Subclasses must implement `parse`."
        end

        def children
          @root.children
        end

        def declaration(options)
          version = options[:declaration].is_a?(String) ? options[:declaration] : "1.0"
          encoding = options[:encoding].is_a?(String) ? options[:encoding] : (options[:encoding] ? "UTF-8" : nil)
          declaration = "<?xml version=\"#{version}\""
          declaration += " encoding=\"#{encoding}\"" if encoding
          declaration += "?>\n"
          declaration
        end
      end

      class Element
        attr_reader :attributes, :children, :text, :namespace, :namespace_prefix

        def initialize(name, attributes = {}, children = [], text = nil, namespace: nil, namespace_prefix: nil)
          @name = name
          @attributes = attributes.map { |k, v| Attribute.new(k, v) }
          @children = children
          @text = text
          @namespace = namespace
          @namespace_prefix = namespace_prefix
        end

        def name
          if namespace && namespace_prefix
            "#{namespace_prefix}:#{@name}"
          else
            @name
          end
        end

        def unprefixed_name
          @name
        end

        def document
          Document.new(self)
        end
      end

      class Attribute
        attr_reader :name, :value, :namespace, :namespace_prefix

        def initialize(name, value, namespace: nil, namespace_prefix: nil)
          @name = name
          @value = value
          @namespace = namespace
          @namespace_prefix = namespace_prefix
        end
      end
    end
  end
end
