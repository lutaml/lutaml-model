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

        def initialize(root, encoding = nil, register: nil)
          @root = root
          @encoding = encoding
          @register = setup_register(register)
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

        def handle_nested_elements(builder, value, options = {})
          element_options = build_options_for_nested_elements(options)

          case value
          when Array
            value.each { |val| build_element(builder, val, element_options) }
          else
            build_element(builder, value, element_options)
          end
        end

        def build_options_for_nested_elements(options = {})
          attribute = options.delete(:attribute)
          rule = options.delete(:rule)

          return {} unless rule

          # options = {}

          options[:namespace_prefix] = rule.prefix if rule&.namespace_set?
          options[:mixed_content] = rule.mixed_content
          options[:tag_name] = rule.name

          options[:mapper_class] = attribute&.type(register) if attribute
          options[:set_namespace] = set_namespace?(rule)

          options
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

          result["attributes"] = attributes_hash(element) if element.attributes&.any?

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

        def build_element(xml, element, options = {})
          if ordered?(element, options)
            build_ordered_element(xml, element, options)
          else
            build_unordered_element(xml, element, options)
          end
        end

        def add_to_xml(xml, element, prefix, value, options = {})
          attribute = options[:attribute]
          rule = options[:rule]

          if rule.custom_methods[:to]
            options[:mapper_class].new.send(rule.custom_methods[:to], element, xml.parent, xml)
            return
          end

          # Only transform when recursion is not called
          if !attribute.collection? || attribute.collection_instance?(value)
            value = ExportTransformer.call(value, rule, attribute)
          end

          if attribute.collection_instance?(value) && !Utils.empty_collection?(value)
            value.each do |item|
              add_to_xml(xml, element, prefix, item, options)
            end

            return
          end

          return if !render_element?(rule, element, value)

          value = rule.render_value_for(value)

          if value && (attribute&.type(register)&.<= Lutaml::Model::Serialize)
            handle_nested_elements(
              xml,
              value,
              options.merge({ rule: rule, attribute: attribute }),
            )
          elsif value.nil?
            xml.create_and_add_element(rule.name, attributes: { "xsi:nil" => true })
          elsif Utils.empty?(value)
            xml.create_and_add_element(rule.name)
          elsif rule.raw_mapping?
            xml.add_xml_fragment(xml, value)
          elsif rule.prefix_set?
            xml.create_and_add_element(rule.name, prefix: prefix) do
              add_value(xml, value, attribute, cdata: rule.cdata)
            end
          else
            xml.create_and_add_element(rule.name) do
              add_value(xml, value, attribute, cdata: rule.cdata)
            end
          end
        end

        def add_value(xml, value, attribute, cdata: false)
          if !value.nil?
            serialized_value = attribute.serialize(value, :xml, register)
            if attribute.raw?
              xml.add_xml_fragment(xml, value)
            elsif attribute.type(register) == Lutaml::Model::Type::Hash
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

        def build_unordered_element(xml, element, options = {})
          mapper_class = determine_mapper_class(element, options)
          xml_mapping = mapper_class.mappings_for(:xml)
          return xml unless xml_mapping

          options[:parent_namespace] ||= nil
          attributes = build_element_attributes(element, xml_mapping, options)
          prefix = determine_namespace_prefix(options, xml_mapping)

          prefixed_xml = xml.add_namespace_prefix(prefix)
          tag_name = options[:tag_name] || xml_mapping.root_element

          return if options[:except]&.include?(tag_name)

          prefixed_xml.create_and_add_element(tag_name, prefix: prefix,
                                                        attributes: attributes) do
            if options.key?(:namespace_prefix) && !options[:namespace_prefix]
              prefixed_xml.add_namespace_prefix(nil)
            end

            xml_mapping.attributes.each do |attribute_rule|
              attribute_rule.serialize_attribute(element, prefixed_xml.parent,
                                                 xml)
            end

            current_namespace = xml_mapping.namespace_uri
            child_options = options.merge({ parent_namespace: current_namespace })

            mappings = xml_mapping.elements + [xml_mapping.raw_mapping].compact
            mappings.each do |element_rule|
              attribute_def = attribute_definition_for(element, element_rule,
                                                       mapper_class: mapper_class)

              next if child_options[:except]&.include?(element_rule.to)

              if attribute_def
                value = attribute_value_for(element, element_rule)

                next if !element_rule.render?(value, element)

                value = attribute_def.build_collection(value) if attribute_def.collection? && !attribute_def.collection_instance?(value)
              end

              add_to_xml(
                prefixed_xml,
                element,
                element_rule.prefix,
                value,
                child_options.merge({ attribute: attribute_def, rule: element_rule,
                                      mapper_class: mapper_class }),
              )
            end

            process_content_mapping(element, xml_mapping.content_mapping,
                                    prefixed_xml, mapper_class)
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
            text = text.join if text.is_a?(Array)

            xml.add_text(xml, text, cdata: content_rule.cdata)
          end
        end

        def ordered?(element, options = {})
          return false unless element.respond_to?(:element_order)
          return element.ordered? if element.respond_to?(:ordered?)
          return options[:mixed_content] if options.key?(:mixed_content)

          mapper_class = options[:mapper_class]
          mapper_class ? mapper_class.mappings_for(:xml).mixed_content? : false
        end

        def set_namespace?(rule)
          rule.nil? || !rule.namespace_set?
        end

        def render_element?(rule, element, value)
          rule.render?(value, element)
        end

        def render_default?(rule, element)
          !element.respond_to?(:using_default?) ||
            rule.render_default? ||
            !element.using_default?(rule.to)
        end

        def build_namespace_attributes(klass, processed = {}, options = {})
          xml_mappings = klass.mappings_for(:xml)
          attributes = klass.attributes
          parent_namespace = options[:parent_namespace]
          is_root_call = options[:is_root_call]

          attrs = {}

          if xml_mappings.namespace_uri && set_namespace?(options[:caller_rule]) && (is_root_call.nil? || is_root_call)
            should_add_xmlns = parent_namespace.nil? ||
              parent_namespace != xml_mappings.namespace_uri

            if should_add_xmlns
              prefixed_name = [
                "xmlns",
                xml_mappings.namespace_prefix,
              ].compact.join(":")

              attrs[prefixed_name] = xml_mappings.namespace_uri
            end
          end

          xml_mappings.mappings.each do |mapping_rule|
            processed[klass] ||= {}

            next if processed[klass][mapping_rule.name]

            processed[klass][mapping_rule.name] = true

            type = if mapping_rule.delegate
                     attributes[mapping_rule.delegate].type(register)
                       .attributes[mapping_rule.to].type(register)
                   else
                     attributes[mapping_rule.to]&.type(register)
                   end

            next unless type

            if type <= Lutaml::Model::Serialize
              child_options = {
                caller_rule: mapping_rule,
                parent_namespace: xml_mappings.namespace_uri || parent_namespace,
                is_root_call: false, # Mark that we're recursing
              }
              child_attrs = build_namespace_attributes(type, processed, child_options)

              child_attrs.each do |key, value|
                attrs[key] = value if key.include?(":")
              end
            end

            if mapping_rule.namespace && mapping_rule.prefix && mapping_rule.name != "lang"
              attrs["xmlns:#{mapping_rule.prefix}"] = mapping_rule.namespace
            end
          end

          attrs
        end

        def build_attributes(element, xml_mapping, options = {})
          parent_namespace = options[:parent_namespace]

          attrs = if options.fetch(:set_namespace, true)
                    namespace_attributes(xml_mapping, parent_namespace)
                  else
                    {}
                  end

          if element.respond_to?(:schema_location) && element.schema_location.is_a?(Lutaml::Model::SchemaLocation) && !options[:except]&.include?(:schema_location)
            attrs.merge!(element.schema_location.to_xml_attributes)
          end

          xml_mapping.attributes.each_with_object(attrs) do |mapping_rule, hash|
            next if mapping_rule.custom_methods[:to] || options[:except]&.include?(mapping_rule.to)

            mapping_rule_name = mapping_rule.multiple_mappings? ? mapping_rule.name.first : mapping_rule.name

            if mapping_rule.namespace && mapping_rule.prefix && mapping_rule_name != "lang"
              hash["xmlns:#{mapping_rule.prefix}"] = mapping_rule.namespace
            end

            value = mapping_rule.to_value_for(element)
            attr = attribute_definition_for(element, mapping_rule, mapper_class: options[:mapper_class])
            value = attr.serialize(value, :xml, register) if attr

            value = ExportTransformer.call(value, mapping_rule, attr)

            if render_element?(mapping_rule, element, value)
              hash[mapping_rule.prefixed_name] = value ? value.to_s : value
            end
          end

          xml_mapping.elements.each_with_object(attrs) do |mapping_rule, hash|
            next if options[:except]&.include?(mapping_rule.to)

            if mapping_rule.namespace && mapping_rule.prefix
              hash["xmlns:#{mapping_rule.prefix}"] = mapping_rule.namespace
            end
          end
        end

        def attribute_definition_for(element, rule, mapper_class: nil)
          klass = mapper_class || element.class
          return klass.attributes[rule.to] unless rule.delegate

          element.send(rule.delegate).class.attributes[rule.to]
        end

        def attribute_value_for(element, rule)
          return element.send(rule.to) unless rule.delegate

          element.send(rule.delegate).send(rule.to)
        end

        def namespace_attributes(xml_mapping, parent_namespace = nil)
          return {} unless xml_mapping.namespace_uri

          return {} if parent_namespace == xml_mapping.namespace_uri

          key = ["xmlns", xml_mapping.namespace_prefix].compact.join(":")
          { key => xml_mapping.namespace_uri }
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

        def determine_namespace_prefix(options, mapping)
          return options[:namespace_prefix] if options.key?(:namespace_prefix)

          mapping.namespace_prefix
        end

        def build_element_attributes(element, mapping, options)
          xml_attributes = options[:xml_attributes] ||= {}
          attributes = build_attributes(element, mapping, options)

          parent_namespace = options[:parent_namespace]
          element_namespace = mapping.namespace_uri
          namespace_inherited = parent_namespace && element_namespace &&
            parent_namespace == element_namespace

          merged_attrs = attributes.dup
          xml_attributes.each do |key, value|
            is_xmlns = key == "xmlns" || key.start_with?("xmlns:")

            next if is_xmlns && namespace_inherited
            next if is_xmlns && merged_attrs.key?(key)

            merged_attrs[key] = value
          end

          merged_attrs&.compact
        end
      end
    end
  end
end
