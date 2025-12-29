require_relative "xml_attribute"
require_relative "document"

module Lutaml
  module Model
    module Xml
      class XmlElement
        XML_NAMESPACE_URI = "http://www.w3.org/XML/1998/namespace".freeze

        attr_reader :attributes,
                    :children,
                    :namespace_prefix,
                    :parent_document

        attr_accessor :adapter_node

        # Detect if xmlns="" is explicitly set (W3C explicit no namespace)
        # This is a helper method for adapters to use during element initialization
        #
        # @param has_empty_xmlns [Boolean] true if xmlns="" is present
        # @param node_namespace_nil [Boolean] true if the node has no namespace
        # @return [Boolean] true if both conditions met (explicit no namespace)
        def self.detect_explicit_no_namespace(has_empty_xmlns:, node_namespace_nil:)
          has_empty_xmlns && node_namespace_nil
        end

        def initialize(
          node,
          attributes = {},
          children = [],
          text = nil,
          name: nil,
          parent_document: nil,
          namespace_prefix: nil,
          default_namespace: nil,
          explicit_no_namespace: false
        )
          @name = name
          @namespace_prefix = namespace_prefix
          @attributes = attributes
          @children = children
          @text = text
          @parent_document = parent_document
          @default_namespace = default_namespace
          @explicit_no_namespace = explicit_no_namespace

          self.adapter_node = node
        end

        # This tells which attributes to pretty print, So we remove the
        # @parent_document and @adapter_node because they were causing
        # so much repeatative output.
        def pretty_print_instance_variables
          (instance_variables - %i[@adapter_node @parent_document]).sort
        end

        def text?
          @name == "text"
        end

        def name
          return @name unless namespace_prefix

          "#{namespace_prefix}:#{@name}"
        end

        def namespaced_name
          return @name if text?
          # If xmlns="" was explicitly set, element has NO namespace
          return @name if @explicit_no_namespace

          # Priority order for namespace resolution:
          # 1. If has explicit prefix, use namespaces[prefix]
          # 2. If has @default_namespace, use it (preferred for default ns)
          # 3. Fall back to namespaces[nil] if exists
          # 4. Return unprefixed name

          if namespace_prefix && namespaces[namespace_prefix]
            "#{namespaces[namespace_prefix].uri}:#{@name}"
          elsif @default_namespace
            "#{@default_namespace}:#{@name}"
          elsif namespaces[nil]
            "#{namespaces[nil].uri}:#{@name}"
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

        def namespaces
          @namespaces || @parent_document&.namespaces || {}
        end

        def own_namespaces
          @namespaces || {}
        end

        def namespace
          return default_namespace unless namespace_prefix

          namespaces[namespace_prefix]
        end

        def attribute_is_namespace?(name)
          name.to_s.start_with?("xmlns")
        end

        def add_namespace(namespace)
          @namespaces ||= {}
          @namespaces[namespace.prefix] = namespace
        end

        def default_namespace
          namespaces[nil] || @parent_document&.namespaces&.dig(nil)
        end

        def order
          children.map do |child|
            type = child.text? ? "Text" : "Element"
            Lutaml::Model::Xml::Element.new(type, child.unprefixed_name)
          end
        end

        def root
          self
        end

        def text
          return @text if children.empty?
          return text_children.map(&:text) if children.count > 1

          text_children.map(&:text).join
        end

        def cdata
          return @text if children.empty?
          return cdata_children.map(&:text) if children.count > 1

          cdata_children.map(&:text).join
        end

        def cdata_children
          find_children_by_name("#cdata-section")
        end

        def text_children
          find_children_by_name("text")
        end

        def [](name)
          find_attribute_value(name) || find_children_by_name(name)
        end

        def find_attribute_value(attribute_name)
          if attribute_name.is_a?(Array)
            attributes.values.find do |attr|
              attribute_name.include?(attr.namespaced_name)
            end&.value
          else
            attributes.values.find do |attr|
              attribute_name == attr.namespaced_name
            end&.value
          end
        end

        def find_children_by_name(name)
          if name.is_a?(Array)
            children.select { |child| name.include?(child.namespaced_name) }
          else
            children.select { |child| child.namespaced_name == name }
          end
        end

        def find_child_by_name(name)
          find_children_by_name(name).first
        end

        def to_h
          document.to_h
        end

        def nil_element?
          find_attribute_value("xsi:nil") == "true"
        end
      end
    end
  end
end
