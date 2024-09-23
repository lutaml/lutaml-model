module Lutaml
  module Model
    module XmlAdapter
      module Builder
        class Nokogiri
          def self.build(options = {})
            if block_given?
              ::Nokogiri::XML::Builder.new(options) do |xml|
                yield(new(xml))
              end
            else
              new(::Nokogiri::XML::Builder.new(options))
            end
          end

          attr_reader :xml

          def initialize(xml)
            @xml = xml
          end

          def create_element(name, attributes = {})
            xml.doc.create_element(name, attributes)
          end

          def add_element(element, child)
            element.add_child(child)
          end

          def add_attribute(element, name, value)
            element[name] = value
          end

          def create_and_add_element(
            element_name,
            prefix: (prefix_unset = true
                     nil),
            attributes: {}
          )
            add_namespace_prefix(prefix)

            if block_given?
              public_send(element_name, attributes) do
                xml.parent.namespace = nil if prefix.nil? && !prefix_unset
                yield(self)
              end
            else
              public_send(element_name, attributes)
            end
          end

          def add_text(element, text)
            if element.is_a?(self.class)
              element = element.xml.parent
            end

            add_element(element, ::Nokogiri::XML::Text.new(text.to_s, xml.doc))
          end

          def add_namespace_prefix(prefix)
            xml[prefix] if prefix

            self
          end

          def method_missing(method_name, *args)
            if block_given?
              xml.public_send(method_name, *args) do
                yield(xml)
              end
            else
              xml.public_send(method_name, *args)
            end
          end

          def respond_to_missing?(method_name, include_private = false)
            xml.respond_to?(method_name) || super
          end
        end
      end
    end
  end
end
