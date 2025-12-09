module Lutaml
  module Model
    module Xml
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
            # CORRECT ARCHITECTURE: Don't use xml[prefix] which requires pre-registration
            # Instead, build the prefixed element name and let xmlns attributes handle resolution
            element_name = element_name.first if element_name.is_a?(Array)
            element_name = "#{element_name}_" if respond_to?(element_name)

            # Build the fully qualified element name if prefix is provided
            qualified_name = if !prefix_unset && prefix
                               "#{prefix}:#{element_name}"
                             else
                               element_name
                             end

            if block_given?
              xml.public_send(qualified_name, attributes) do
                xml.parent.namespace = nil if prefix.nil? && !prefix_unset
                yield(self)
              end
            else
              xml.public_send(qualified_name, attributes)
            end
          end

          def add_xml_fragment(element, content)
            element = element.xml.parent if element.is_a?(self.class)

            fragment = ::Nokogiri::XML::DocumentFragment.parse(content)

            element.add_child(fragment)
          end

          def add_text(element, text, cdata: false)
            return add_cdata(element, text) if cdata

            element = element.xml.parent if element.is_a?(self.class)

            text_node = ::Nokogiri::XML::Text.new(text.to_s, element)
            element.add_child(text_node)
          end

          def add_cdata(element, value)
            if element.is_a?(self.class)
              element = element.xml.parent
            end

            cdata_node = ::Nokogiri::XML::CDATA.new(element.document,
                                                    value.to_s)
            element.add_child(cdata_node)
          end

          def add_namespace_prefix(prefix)
            xml[prefix] if prefix

            self
          end

          def method_missing(method_name, *args, &block)
            if block
              xml.public_send(method_name, *args, &block)
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
