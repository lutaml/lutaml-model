# frozen_string_literal: true

module Lutaml
  module Xml
    module Builder
      class Oga
        def self.build(options = {}, &)
          new(options, &)
        end

        attr_reader :document, :current_node, :encoding

        def initialize(options = {})
          @document = Xml::Oga::Document.new
          @moxml_doc = @document.moxml_doc
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
          moxml_element = @moxml_doc.create_element(name)
          element_attributes(moxml_element, attributes)
          @current_node.add_child(moxml_element)

          if block_given?
            previous_node = @current_node
            @current_node = moxml_element
            yield(self)
            @current_node = previous_node
          end
          moxml_element
        end

        def add_element(target, child)
          if child.is_a?(String)
            add_xml_fragment(target, child)
          else
            target.add_child(child)
          end
        end

        def add_attribute(target, name, value)
          target[name] = value.to_s
        end

        def create_and_add_element(
          element_name,
          prefix: (prefix_unset = true
                   nil),
          attributes: {},
          &block
        )
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

        def add_xml_fragment(target, content)
          fragment = "<fragment>#{content}</fragment>"
          parsed_doc = @document.context.parse(fragment)
          parsed_root = parsed_doc.root
          return unless parsed_root

          parsed_root.children.each do |child|
            target.add_child(child)
          end
        end

        def add_text(target, text, cdata: false)
          text = encode_value(text)
          return add_cdata(target, text) if cdata

          target = target.current_node if target.is_a?(self.class)

          moxml_text = @moxml_doc.create_text(text.to_s)
          target.add_child(moxml_text)
        end

        def add_cdata(target, value)
          moxml_cdata = @moxml_doc.create_cdata(value.to_s)
          target.add_child(moxml_cdata)
        end

        def add_comment(target, value)
          value = encode_value(value)
          moxml_comment = @moxml_doc.create_comment(value.to_s)
          # When target is the Document, add to root element (not document level)
          actual_target = target.is_a?(Xml::Oga::Document) ? target.root : target
          actual_target.add_child(moxml_comment)
        end

        def add_namespace_prefix(prefix)
          @current_namespace = prefix
          self
        end

        def parent
          @document
        end

        def doc
          @document
        end

        def text(value = nil)
          return @current_node.inner_text if value.nil?

          str = value.is_a?(Array) ? value.join : value.to_s
          moxml_text = @moxml_doc.create_text(str)
          @current_node.add_child(moxml_text)
        end

        def to_xml
          @moxml_doc.to_xml(no_declaration: true)
        end

        def method_missing(method_name, *args)
          delegatee = resolve_delegatee
          unless delegatee
            raise NoMethodError,
                  "cannot delegate method `#{method_name}' to non-XML node #{@current_node.inspect}"
          end

          if delegatee.respond_to?(method_name)
            args = [args.first.to_s] if method_name == :text && args.size == 1 && !args.first.is_a?(String)

            if block_given?
              delegatee.public_send(method_name, *args) { yield(self) }
            else
              delegatee.public_send(method_name, *args)
            end
          else
            raise NoMethodError,
                  "undefined method `#{method_name}' for #{delegatee.inspect}"
          end
        end

        def respond_to_missing?(method_name, include_private = false)
          resolve_delegatee.respond_to?(method_name) || super
        end

        private

        def encode_value(value)
          return value unless encoding && value.is_a?(String)

          value.encode(encoding)
        end

        def resolve_delegatee
          case @current_node
          when Xml::Oga::Document then @current_node.moxml_doc
          when Moxml::Node then @current_node
          end
        end

        def element_attributes(moxml_element, attributes)
          return unless attributes

          attributes = attributes.compact if attributes.respond_to?(:compact)

          # Filter out duplicate xmlns declarations already on parent chain
          filtered_attributes = attributes.reject do |name, _value|
            name.to_s.start_with?("xmlns") && parent_has_xmlns?(@current_node,
                                                                name, attributes[name])
          end

          filtered_attributes.each do |name, value|
            value = value.uri unless value.is_a?(String)
            moxml_element[name.to_s] = value.to_s
          end
        end

        # Walk parent chain checking for duplicate xmlns declarations.
        # Document responds to #attributes (delegates to root) and #parent (nil),
        # so the loop terminates naturally at the document boundary.
        def parent_has_xmlns?(node, xmlns_name, xmlns_value)
          visited = Set.new
          current = node
          xmlns_name_str = xmlns_name.to_s

          while current.respond_to?(:attributes)
            break if visited.include?(current.object_id)

            visited.add(current.object_id)

            existing = current.attributes&.find do |attr|
              attr.name.to_s == xmlns_name_str && attr.value == xmlns_value
            end
            return true if existing

            break unless current.respond_to?(:parent) && current.parent

            current = current.parent
          end
          false
        end
      end
    end
  end
end
