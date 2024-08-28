module Lutaml
  module Model
    module XmlAdapter
      module Builder
        class Ox
          def self.build(options = {})
            if block_given?
              ::Ox::Builder.new(options) do |xml|
                yield(new(xml))
              end
            else
              new(::Ox::Builder.new(options))
            end
          end

          attr_reader :xml

          def initialize(xml)
            @xml = xml
          end

          def create_element(name, attributes = {})
            if block_given?
              xml.element(name, attributes) do |element|
                yield(self.class.new(element))
              end
            else
              xml.element(name, attributes)
            end
          end

          def add_element(element, child)
            element << child
          end

          def create_and_add_element(element_name, prefix: nil, attributes: {})
            prefixed_name = if prefix
                              "#{prefix}:#{element_name}"
                            else
                              element_name
                            end

            if block_given?
              xml.element(prefixed_name, attributes) do |element|
                yield(self.class.new(element))
              end
            else
              xml.element(prefixed_name, attributes)
            end
          end

          def <<(text)
            xml.text(text)
          end

          def add_text(element, text)
            element << text
          end

          # Add XML namespace to document
          #
          # Ox doesn't support XML namespaces so this method does nothing.
          def add_namespace_prefix(_prefix)
            # :noop:
            self
          end

          def parent
            xml
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
