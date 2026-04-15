module Lutaml
  module Xml
    module Builder
      class Ox
        # Internal XML builder that uses moxml Document API instead of
        # Ox::Builder directly. Provides the same element/text/cdata/raw/to_s
        # interface that the wrapper and adapter code expects.
        class MoxmlXmlBuilder
          def initialize(_options = {})
            @context = Moxml.new(:ox)
            @document = @context.create_document
            @stack = [@document]
          end

          def element(name, attributes = {})
            el = @document.create_element(name)
            attributes.each do |k, v|
              key = k.to_s
              if key == "xmlns" || key.start_with?("xmlns:")
                prefix = key == "xmlns" ? nil : key.delete_prefix("xmlns:")
                el.add_namespace(prefix, v.to_s)
              else
                el[key] = v.to_s
              end
            end
            @stack.last.add_child(el)

            if block_given?
              @stack.push(el)
              yield self
              @stack.pop
            end

            el
          end

          def text(content)
            @stack.last.add_child(@document.create_text(content.to_s))
          end

          def cdata(content)
            @stack.last.add_child(@document.create_cdata(content.to_s))
          end

          def comment(content)
            @stack.last.add_child(@document.create_comment(content.to_s))
          end

          def raw(content)
            return if content.nil? || content.to_s.empty?

            # Parse raw XML fragment wrapped in a temporary element,
            # then move the parsed children into the current element.
            wrapped = "<__raw__>#{content}</__raw__>"
            temp_doc = @context.parse(wrapped)
            temp_root = temp_doc.root
            temp_root.children.each do |child|
              @stack.last.add_child(child)
            end
          rescue Moxml::ParseError
            # Fallback: insert as escaped text if fragment is not valid XML
            text(content.to_s)
          end

          def to_s
            @document.children.map do |child|
              child.to_xml(no_declaration: true)
            end.join
          end
        end

        def self.build(options = {})
          builder = MoxmlXmlBuilder.new(options)

          if block_given?
            wrapper = new(builder, options)
            yield(wrapper)
            wrapper
          else
            new(builder, options)
          end
        end

        attr_reader :xml, :encoding

        def initialize(xml, options = {})
          @xml = xml
          @encoding = options[:encoding]
          @current_namespace = nil
        end

        def create_element(name, attributes = {})
          if @current_namespace && !name.start_with?("#{@current_namespace}:")
            name = "#{@current_namespace}:#{name}"
          end

          if block_given?
            xml.element(name, attributes) do |element|
              yield(self.class.new(element, { encoding: encoding }))
            end
          else
            xml.element(name, attributes)
          end
        end

        def add_element(element, child)
          element << child
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
          element_name = element_name.first if element_name.is_a?(Array)

          # When prefix is provided (not nil), use it for namespaced element
          # When prefix is nil and explicitly set, don't use any prefix (default namespace)
          # When prefix is unset, use current_namespace if available (backward compatibility)
          prefixed_name = if !prefix_unset && prefix
                            "#{prefix}:#{element_name}"
                          elsif prefix_unset && @current_namespace && !element_name.start_with?("#{@current_namespace}:")
                            "#{@current_namespace}:#{element_name}"
                          else
                            element_name
                          end

          if block_given?
            xml.element(prefixed_name, attributes) do |element|
              yield(self.class.new(element, { encoding: encoding }))
            end
          else
            xml.element(prefixed_name, attributes)
          end

          @current_namespace = nil
        end

        def set_prefixed_name(element_name, prefix)
          if prefix
            "#{prefix}:#{element_name}"
          elsif @current_namespace && !element_name.start_with?("#{@current_namespace}:")
            "#{@current_namespace}:#{element_name}"
          else
            element_name
          end
        end

        def <<(text)
          xml.text(text)
        end

        def add_xml_fragment(element, content)
          element.raw(content)
        end

        def add_text(element, text, cdata: false)
          text = text&.encode(encoding) if encoding && text.is_a?(String)

          return element.cdata(text) if cdata

          element.text(text)
        end

        def add_cdata(element, value)
          element.cdata(value)
        end

        def add_comment(content)
          xml.comment(content)
        end

        # Add XML namespace to document
        #
        # Ox doesn't support XML namespaces so we only save the
        # current namespace prefix to add it to the element's name later.
        def add_namespace_prefix(prefix)
          @current_namespace = prefix
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
