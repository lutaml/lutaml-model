# frozen_string_literal: true

module Lutaml
  module Model
    module XmlAdapter
      module Builder
        class Oga
          def self.build(options = {})
            options[:indent_string] = ""
            if block_given?
              XmlAdapter::Builder::Oga.new(options) do |xml|
                yield(xml)
              end
            else
              XmlAdapter::Builder::Oga.new(options)
            end
          end

          attr_reader :document, :current_node, :options

          def initialize(options = {})
            @document = XmlAdapter::Oga::Document.new
            @current_node = @document
            @options = options
            yield(self) if block_given?
          end

          def create_element(name, attributes = {})
            if @current_namespace && !name.start_with?("#{@current_namespace}:")
              name = "#{@current_namespace}:#{name}"
            end

            if block_given?
              element(name, attributes) do |element|
                yield(element)
              end
            else
              element(name, attributes)
            end
          end

          def element(name, attributes = {}, &block)
            oga_element = ::Oga::XML::Element.new(name: name)
            element_attributes(oga_element, attributes)
            # Add newline only if the @current_node is an oga element
            text("\n#{options[:indent_string]}") if @current_node.is_a?(::Oga::XML::Element)
            @current_node.children << oga_element
            # Save previous node to reset the pointer for the rest of the iteration
            previous_node = @current_node
            # Set current node to new element as pointer for the block
            @current_node = oga_element
            # Increase indent for the next element
            indent = options[:indent_string]
            options[:indent_string] = "  " + indent
            yield(self) if block_given?
            # Reset the pointer for the rest of the iterations
            @current_node = previous_node
            # Reset indent for this iteration
            options[:indent_string] = indent
            oga_element
          end

          def add_element(element, child)
            element << child
          end

          def add_attribute(element, name, value)
            element[name] = value
          end

          def create_and_add_element(element_name, prefix: nil, attributes: {})
            prefixed_name = if prefix
                              "#{prefix}:#{element_name}"
                            elsif @current_namespace && !element_name.start_with?("#{@current_namespace}:")
                              "#{@current_namespace}:#{element_name}"
                            else
                              element_name
                            end

            if block_given?
              element(prefixed_name, attributes) do |element|
                yield(element)
              end
            else
              element(prefixed_name, attributes)
            end

            @current_namespace = nil
          end

          def <<(text)
            @current_node.text(text)
          end

          def add_xml_fragment(element, content)
            element.raw(content)
          end

          def add_text(element, text, cdata: false)
            return add_cdata(element, text) if cdata

            element.children << ::Oga::XML::Text.new(text: text.to_s)
          end

          def add_cdata(element, value)
            element.children << ::Oga::XML::CData.new(text: value.to_s)
          end

          def add_namespace_prefix(prefix)
            @current_namespace = prefix
            self
          end

          def parent
            @document
          end

          def text(value = nil)
            return @current_node.inner_text if value.nil?

            str = value.is_a?(Array) ? value.join : value
            @current_node.children << ::Oga::XML::Text.new(text: str)
          end

          def method_missing(method_name, *args)
            if block_given?
              @current_node.public_send(method_name, *args) do
                yield(self)
              end
            else
              @current_node.public_send(method_name, *args)
            end
          end

          def respond_to_missing?(method_name, include_private = false)
            @current_node.respond_to?(method_name) || super
          end

          private

          def element_attributes(oga_element, attributes)
            oga_element.attributes = attributes.map do |name, value|
              ::Oga::XML::Attribute.new(
                name: name,
                value: value,
                element: oga_element,
              )
            end
          end
        end
      end
    end
  end
end
