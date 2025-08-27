# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      module Builder
        class Rexml
          def self.build(options = {}, &block)
            new(options, &block)
          end

          attr_reader :doc, :current_node, :encoding

          def initialize(options = {})
            @doc = ::REXML::Document.new
            @current_node = @doc
            @encoding = options[:encoding]

            # Add XML declaration if requested
            if options[:encoding] || options[:version]
              declaration = ::REXML::XMLDecl.new(
                options[:version] || "1.0",
                options[:encoding],
                options[:standalone],
              )
              @doc << declaration
            end

            yield(self) if block_given?
          end

          def create_element(name, attributes = {})
            element = ::REXML::Element.new(name.to_s)
            attributes.each { |key, value| element.attributes[key.to_s] = value.to_s }
            element
          end

          def element(name, attributes = {})
            rexml_element = ::REXML::Element.new(name)
            if block_given?
              element_attributes(rexml_element, attributes)
              @current_node.add_element(rexml_element)
              # Save previous node to reset the pointer for the rest of the iteration
              previous_node = @current_node
              # Set current node to new element as pointer for the block
              @current_node = rexml_element
              yield(self)
              # Reset the pointer for the rest of the iterations
              @current_node = previous_node
            else
              element_attributes(rexml_element, attributes)
              @current_node.add_element(rexml_element)
            end
            rexml_element
          end

          def element_attributes(element, attributes)
            attributes.each do |key, value|
              element.attributes[key.to_s] = value.to_s
            end
          end

          def create_and_add_element(
            element_name,
            prefix: nil,
            attributes: {}
          )
            prefixed_name = if prefix
                              "#{prefix}:#{element_name}"
                            else
                              element_name
                            end

            if block_given?
              element(prefixed_name, attributes) do
                yield(self)
              end
            else
              element(prefixed_name, attributes)
            end
          end

          def add_text(element, text, cdata: false)
            text_node = if cdata
                          ::REXML::CData.new(text.to_s)
                        else
                          ::REXML::Text.new(text.to_s, true)
                        end
            element << text_node
          end

          def text(content)
            @current_node.add_text(::REXML::Text.new(content.to_s, true))
          end

          def <<(text)
            text_node = ::REXML::Text.new(text.to_s, true)
            @current_node << text_node
          end

          def add_namespace_prefix(_prefix)
            self
          end

          def parent
            @current_node
          end

          def method_missing(name, *args, &block)
            attributes = args.first.is_a?(Hash) ? args.first : {}
            element(name, attributes, &block)
          end

          def respond_to_missing?(_name, _include_private = false)
            true
          end

          def to_s
            output = +"" # Use unary plus to create mutable string
            @doc.write(output, 2)
            output
          end

          def to_xml
            to_s
          end
        end
      end
    end
  end
end
