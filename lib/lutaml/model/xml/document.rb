require_relative "../mapping_hash"
require_relative "xml_element"
require_relative "xml_attribute"
require_relative "xml_namespace"
require_relative "element"

module Lutaml
  module Model
    module Xml
      class Document
        attr_reader :root, :encoding, :register

        def initialize(root, encoding = nil, register: nil, **options)
          @root = root
          @encoding = encoding
          @register = setup_register(register)
          @options = options # NEW: Store options
        end

        def self.parse(xml, _options = {})
          raise NotImplementedError, "Subclasses must implement `parse`."
        end

        def children
          @root.children
        end

        def attributes
          root.attributes
        end

        def self.encoding(xml, options)
          if options.key?(:encoding)
            options[:encoding]
          else
            xml.encoding.to_s
          end
        end

        def declaration(options)
          version = "1.0"
          version = options[:declaration] if options[:declaration].is_a?(String)

          encoding = options[:encoding] ? "UTF-8" : nil
          encoding = options[:encoding] if options[:encoding].is_a?(String)

          declaration = "<?xml version=\"#{version}\""
          declaration += " encoding=\"#{encoding}\"" if encoding
          declaration += "?>\n"
          declaration
        end

        def to_h
          parse_element(@root)
        end

        def order
          @root.order
        end

        def parse_element(element, klass = nil, format = nil)
          result = Lutaml::Model::MappingHash.new
          result.node = element
          result.item_order = self.class.order_of(element)

          element.children.each do |child|
            if klass&.<= Serialize
              attr = klass.attribute_for_child(self.class.name_of(child),
                                               format)
            end

            if child.respond_to?(:text?) && child.text?
              result.assign_or_append_value(
                self.class.name_of(child),
                self.class.text_of(child),
              )
              next
            end

            result["elements"] ||= Lutaml::Model::MappingHash.new
            result["elements"].assign_or_append_value(
              self.class.namespaced_name_of(child),
              parse_element(child, attr&.type(register) || klass, format),
            )
          end

          if element.attributes&.any?
            result["attributes"] =
              attributes_hash(element)
          end

          result.merge(attributes_hash(element))
          result
        end

        def attributes_hash(element)
          result = Lutaml::Model::MappingHash.new

          element.attributes.each_value do |attr|
            if attr.unprefixed_name == "schemaLocation"
              result["__schema_location"] = {
                namespace: attr.namespace,
                prefix: attr.namespace_prefix,
                schema_location: attr.value,
              }
            else
              result[attr.namespaced_name] = attr.value
            end
          end

          result
        end

        def ordered?(element, options = {})
          return false unless element.respond_to?(:element_order)
          return element.ordered? if element.respond_to?(:ordered?)
          return options[:mixed_content] if options.key?(:mixed_content)

          mapper_class = options[:mapper_class]
          mapper_class ? mapper_class.mappings_for(:xml).mixed_content? : false
        end

        def render_element?(rule, element, value)
          rule.render?(value, element)
        end

        def add_value(xml, value, attribute, cdata: false)
          if !value.nil?
            if attribute.nil?
              # For delegated attributes where attribute is nil, just use the raw value
              xml.add_text(xml, value.to_s, cdata: cdata)
            elsif attribute.transform.is_a?(Class) && attribute.transform < Lutaml::Model::ValueTransformer
              # Check if value has already been transformed by a class-based transformer
              # If so, use it directly without going through attribute.serialize
              # Value has already been transformed, use it directly
              xml.add_text(xml, value.to_s, cdata: cdata)
            else
              # Normal serialization through attribute type system
              serialized_value = attribute.serialize(value, :xml, register)
              if attribute.raw?
                xml.add_xml_fragment(xml, value)
              elsif serialized_value.is_a?(Hash)
                serialized_value.each do |key, val|
                  xml.create_and_add_element(key) do |element|
                    element.text(val)
                  end
                end
              else
                xml.add_text(xml, serialized_value, cdata: cdata)
              end
            end
          end
        end

        def process_content_mapping(element, content_rule, xml, mapper_class)
          return unless content_rule

          if content_rule.custom_methods[:to]
            mapper_class.new.send(
              content_rule.custom_methods[:to],
              element,
              xml.parent,
              xml,
            )
          else
            text = content_rule.serialize(element)
            cdata = content_rule.cdata
            if text.is_a?(Array) && !cdata && element.element_order&.any?
              element.element_order&.each_with_index do |object, index|
                str = text[index]
                if object.entity?
                  xml.add_entity(xml, str)
                elsif object.text?
                  xml.add_text(xml, str, cdata: cdata)
                end
              end
            else
              text = text.join if text.is_a?(Array)

              xml.add_text(xml, text, cdata: cdata)
            end
          end
        end

        def attribute_definition_for(element, rule, mapper_class: nil)
          klass = mapper_class || element.class
          return klass.attributes[rule.to] unless rule.delegate

          delegated_obj = element.send(rule.delegate)
          return nil if delegated_obj.nil?

          delegated_obj.class.attributes[rule.to]
        end

        def attribute_value_for(element, rule)
          return element.send(rule.to) unless rule.delegate

          element.send(rule.delegate).send(rule.to)
        end

        def self.type
          Utils.snake_case(self).split("/").last.split("_").first
        end

        def self.order_of(element)
          element.order
        end

        def self.name_of(element)
          element.name
        end

        def self.text_of(element)
          element.text
        end

        def self.namespaced_name_of(element)
          element.namespaced_name
        end

        def text
          return @root.text_children.map(&:text) if @root.children.count > 1

          @root.text
        end

        def cdata
          @root.cdata
        end

        private

        def setup_register(register)
          return register if register.is_a?(Symbol)

          return_register = if register.is_a?(Lutaml::Model::Register)
                              register.id
                            elsif @root.respond_to?(:__register)
                              @root.__register
                            elsif @root.instance_variable_defined?(:@__register)
                              @root.instance_variable_get(:@__register)
                            end
          return_register || Lutaml::Model::Config.default_register
        end

        def determine_mapper_class(element, options)
          if options[:mapper_class] && element.is_a?(options[:mapper_class])
            element.class
          else
            options[:mapper_class] || element.class
          end
        end

        # Resolve namespace for element using MappingRule.resolve_namespace
        #
        # @param rule [MappingRule] the mapping rule
        # @param attribute [Attribute] the attribute being mapped
        # @param options [Hash] serialization options
        # @return [Hash] namespace info { uri:, prefix:, ns_class: }
        def resolve_element_namespace(rule, attribute, options = {})
          return { uri: nil, prefix: nil, ns_class: nil } unless rule

          parent_ns_uri = options[:parent_namespace]
          mapper_class = options[:mapper_class]

          # Try to get parent namespace class if available
          parent_ns_class = if mapper_class.respond_to?(:mappings_for)
                              mapper_class.mappings_for(:xml)&.namespace_class
                            end

          # Default form is unqualified unless specified
          form_default = :qualified

          # Pass use_prefix from options to enable prefix: true behavior
          # Check both @options (root level) and options hash (propagated to children)
          use_prefix_option = options[:use_prefix] || @options&.[](:use_prefix)

          rule.resolve_namespace(
            attr: attribute,
            register: register,
            parent_ns_uri: parent_ns_uri,
            parent_ns_class: parent_ns_class,
            form_default: form_default,
            use_prefix: use_prefix_option,
            parent_prefix: options.fetch(:parent_prefix, nil),
          )
        end

        # Resolve namespace for attribute using MappingRule.resolve_namespace
        #
        # @param rule [MappingRule] the mapping rule
        # @param attribute [Attribute] the attribute being mapped
        # @param options [Hash] serialization options
        # @return [Hash] namespace info { uri:, prefix:, ns_class: }
        def resolve_attribute_namespace(rule, attribute, options = {})
          return { uri: nil, prefix: nil, ns_class: nil } unless rule

          mapper_class = options[:mapper_class]

          # Get parent namespace class if available
          parent_ns_class = if mapper_class.respond_to?(:mappings_for)
                              mapper_class.mappings_for(:xml)&.namespace_class
                            end

          # Get attribute form default from parent's schema (namespace class)
          form_default = parent_ns_class&.attribute_form_default || :unqualified

          # Attributes follow schema-level attributeFormDefault setting
          rule.resolve_namespace(
            attr: attribute,
            register: register,
            parent_ns_uri: parent_ns_class&.uri,
            parent_ns_class: parent_ns_class,
            form_default: form_default,
          )
        end

        # Check if a namespace URI is in the namespace_scope
        #
        # @param namespace_uri [String] the namespace URI to check
        # @param namespace_scope [Array<Class, Hash>] array of XmlNamespace classes or Hash configs
        # @return [Boolean] true if namespace is in scope
        def namespace_in_scope?(namespace_uri, namespace_scope)
          return false unless namespace_scope&.any?

          namespace_scope.any? do |ns_entry|
            # Handle both Class and Hash formats
            ns_class = if ns_entry.is_a?(Hash)
                         ns_entry[:namespace]
                       else
                         ns_entry
                       end

            ns_class.respond_to?(:uri) && ns_class.uri == namespace_uri
          end
        end
      end
    end
  end
end
