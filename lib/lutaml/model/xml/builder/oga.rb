# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      module Builder
        class Oga
          def self.build(options = {}, &block)
            new(options, &block)
          end

          attr_reader :document, :current_node, :encoding

          def initialize(options = {})
            @document = Xml::Oga::Document.new
            @current_node = @document
            @encoding = options[:encoding]
            yield(self) if block_given?
          end

          def create_element(name, attributes = {}, &block)
            if @current_namespace && !name.start_with?("#{@current_namespace}:")
              name = "#{@current_namespace}:#{name}"
            end

            if block
              element(name, attributes, &block)
            else
              element(name, attributes)
            end
          end

          def element(name, attributes = {})
            oga_element = ::Oga::XML::Element.new(name: name)
            element_attributes(oga_element, attributes)
            @current_node.children << oga_element

            if block_given?
              # Save previous node to reset the pointer for the rest of the iteration
              previous_node = @current_node
              # Set current node to new element as pointer for the block
              @current_node = oga_element
              yield(self)
              # Reset the pointer for the rest of the iterations
              @current_node = previous_node
            end
            oga_element
          end

          def add_element(oga_element, child)
            if child.is_a?(String)
              current_element = oga_element.is_a?(Xml::Oga::Document) ? current_node : oga_element
              add_xml_fragment(current_element, child)
            elsif oga_element.is_a?(Xml::Oga::Document)
              oga_element.children.last.children << child
            else
              oga_element.children << child
            end
          end

          def add_attribute(element, name, value)
            attribute = ::Oga::XML::Attribute.new(
              name: name,
              value: value.to_s,
            )
            if element.is_a?(Xml::Oga::Document)
              element.children.last.attributes << attribute
            else
              element.attributes << attribute
            end
          end

          def create_and_add_element(
            element_name,
            prefix: (prefix_unset = true
                     nil),
            attributes: {},
            &block
          )
            # When prefix is provided (not nil), use it for namespaced element
            # When prefix is nil and explicitly set, clear namespace and use bare element name (default namespace)
            # When prefix is unset, use current_namespace if available (backward compatibility)
            @current_namespace = nil if prefix.nil? && !prefix_unset

            prefixed_name = if !prefix_unset && prefix
                              "#{prefix}:#{element_name}"
                            elsif prefix_unset && @current_namespace && !element_name.start_with?("#{@current_namespace}:")
                              "#{@current_namespace}:#{element_name}"
                            else
                              element_name
                            end

            if block
              element(prefixed_name, attributes, &block)
            else
              element(prefixed_name, attributes)
            end
          end

          def <<(text)
            @current_node.text(text.to_s)
          end

          def add_xml_fragment(element, content)
            fragment = "<fragment>#{content}</fragment>"
            parsed_fragment = ::Oga.parse_xml(fragment)
            parsed_children = parsed_fragment.children.first.children
            if element.is_a?(Xml::Oga::Document)
              element.children.last.children += parsed_children
            else
              element.children += parsed_children
            end
          end

          def add_text(element, text, cdata: false)
            text = text&.encode(encoding) if encoding && text.is_a?(String)
            return add_cdata(element, text) if cdata

            # Handle case where element is a Builder instance
            if element.is_a?(self.class)
              element = element.current_node
            end

            oga_text = ::Oga::XML::Text.new(text: text.to_s)
            append_text_node(element, oga_text)
          end

          def append_text_node(element, oga_text)
            if element.is_a?(Xml::Oga::Document)
              children = element.children
              children.empty? ? children << oga_text : children.last.children << oga_text
            else
              element.children << oga_text
            end
          end

          def add_cdata(element, value)
            oga_cdata = ::Oga::XML::CData.new(text: value.to_s)
            if element.is_a?(Xml::Oga::Document)
              element.children.last.children << oga_cdata
            else
              element.children << oga_cdata
            end
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

            str = if value.is_a?(Array)
                    value.join
                  else
                    value.to_s
                  end
            @current_node.children << ::Oga::XML::Text.new(text: str.to_s)
          end

          def method_missing(method_name, *args)
            # Guard against invalid delegation - only delegate to @current_node
            # if it's an Oga element that can handle XML methods
            # Integer values (age 30) should not receive XML method calls
            unless @current_node.is_a?(::Oga::XML::Element) ||
                  @current_node.is_a?(::Oga::XML::Document) ||
                  @current_node.is_a?(::Oga::XML::Text) ||
                  @current_node.is_a?(::Oga::XML::CData) ||
                  @current_node.is_a?(::Oga::XML::Attribute)
              raise NoMethodError, "cannot delegate method `#{method_name}' to non-XML node #{@current_node.inspect} (expected Oga element, got #{@current_node.class})"
            end

            if @current_node.respond_to?(method_name)
              # Special handling for text method: ensure type conversion
              # Oga expects String for text content, but caller may pass Integer/Float
              if method_name == :text && args.size == 1 && !args.first.is_a?(String)
                args = [args.first.to_s]
              end

              if block_given?
                @current_node.public_send(method_name, *args) do
                  yield(self)
                end
              else
                @current_node.public_send(method_name, *args)
              end
            else
              # Method not found on @current_node, raise standard NoMethodError
              raise NoMethodError, "undefined method `#{method_name}' for #{@current_node.inspect}"
            end
          end

          def respond_to_missing?(method_name, include_private = false)
            @current_node.respond_to?(method_name) || super
          end

          private

          def element_attributes(oga_element, attributes)
            return unless attributes

            attributes = attributes.compact if attributes.respond_to?(:compact)

            # CRITICAL FIX (Session 197): Filter out duplicate xmlns declarations
            # Nokogiri automatically handles this, but Oga needs explicit filtering
            # Check parent chain for existing xmlns declarations
            filtered_attributes = attributes.reject do |name, value|
              if name.to_s.start_with?("xmlns")
                # Check if this xmlns is already declared on a parent
                # Use @current_node which will be the parent of this element
                parent_has_xmlns?(@current_node, name, value)
              else
                false
              end
            end

            oga_element.attributes = filtered_attributes.map do |name, value|
              value = value.uri unless value.is_a?(String)

              ::Oga::XML::Attribute.new(
                name: name,
                value: value,
                element: oga_element,
              )
            end
          end

          # Check if an xmlns declaration exists on any parent element
          #
          # @param element [Oga::XML::Element] the current parent element
          # @param xmlns_name [String] the xmlns attribute name (e.g., "xmlns", "xmlns:dc")
          # @param xmlns_value [String] the namespace URI
          # @return [Boolean] true if parent chain has matching xmlns
          def parent_has_xmlns?(element, xmlns_name, xmlns_value)
            visited = Set.new
            current = element

            while current && current.respond_to?(:attributes)
              # Prevent infinite loops
              break if visited.include?(current.object_id)
              visited.add(current.object_id)

              # Check if this element has the xmlns with same value
              existing_xmlns = current.attributes.find { |attr| attr.name == xmlns_name }
              return true if existing_xmlns && existing_xmlns.value == xmlns_value

              # Stop at Document boundary
              break if current.is_a?(Xml::Oga::Document)

              current = current.parent if current.respond_to?(:parent)
            end
            false
          end
        end
      end
    end
  end
end
