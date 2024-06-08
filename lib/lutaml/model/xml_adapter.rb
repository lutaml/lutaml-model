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
      end

      class Element
        attr_reader :name, :attributes, :children, :text

        def initialize(name, attributes = {}, children = [], text = nil)
          @name = name
          @attributes = attributes.map { |k, v| Attribute.new(k, v) }
          @children = children
          @text = text
        end

        def document
          Document.new(self)
        end
      end

      class Attribute
        attr_reader :name, :value

        def initialize(name, value)
          @name = name
          @value = value
        end
      end
    end
  end
end
