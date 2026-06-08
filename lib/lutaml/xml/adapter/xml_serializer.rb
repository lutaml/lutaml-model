# frozen_string_literal: true

module Lutaml
  module Xml
    module Adapter
      # Handles the XML serialization pipeline.
      #
      # Responsible for converting model instances and XmlElement trees
      # into XML output via builder objects. Includes the top-level
      # `to_xml` entry point and supporting methods for rendering
      # XmlElement structures with namespace declaration plans.
      module XmlSerializer
        # Add text content to XML builder
        #
        # @param xml [Builder] the XML builder
        # @param value [Object] the value to add
        # @param attribute [Attribute, nil] the attribute definition
        # @param cdata [Boolean] whether to use CDATA
        def add_value(xml, value, attribute, cdata: false)
          if !value.nil?
            if attribute.nil?
              # For delegated attributes where attribute is nil, just use the raw value
              xml.add_text(xml, value.to_s, cdata: cdata)
            elsif attribute.transform.is_a?(Class) && attribute.transform < Lutaml::Model::ValueTransformer
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

        def to_xml(options = {})
          # Accept xml_declaration from options if present (for model serialization)
          @xml_declaration = options[:xml_declaration] if options[:xml_declaration]

          encoding = determine_encoding(options)
          builder_options = {}
          builder_options[:encoding] = encoding if encoding
          if options.key?(:line_ending)
            builder_options[:line_ending] =
              options[:line_ending]
          end
          builder_options[:indent] = options[:indent] if options.key?(:indent)

          # Pass doctype to builder for document-level insertion
          doctype_to_use = options[:doctype] || @doctype
          if doctype_to_use && !options[:omit_doctype]
            builder_options[:doctype] = doctype_to_use
          end

          # Pass declaration info to builder
          if should_include_declaration?(options)
            builder_options[:include_declaration] = true
            builder_options[:xml_declaration] = @xml_declaration || {}
            if options.key?(:standalone)
              if options[:standalone] == :preserve
                # Keep original standalone from parsed declaration (may be nil)
              else
                builder_options[:xml_declaration][:standalone] =
                  standalone_value(options[:standalone])
              end
            end
            if options[:declaration].is_a?(String)
              builder_options[:xml_declaration][:version] =
                options[:declaration]
            elsif options[:declaration] == true
              builder_options[:xml_declaration][:version] = "1.0"
            end
            if options.key?(:encoding) && encoding
              builder_options[:xml_declaration][:encoding] =
                encoding
            end
          elsif options[:encoding] && !options[:encoding].nil?
            builder_options[:force_declaration] = true
          end

          builder = self.class::BUILDER_CLASS.build(builder_options) do |xml|
            if root.is_a?(self.class::PARSED_ELEMENT_CLASS)
              root.build_xml(xml)
            else
              build_serializable_xml(xml, options)
            end
          end

          builder.to_xml
        end

        def build_serializable_xml(xml, options)
          original_model = nil
          xml_element = transformable_xml_element(options) do |model|
            original_model = model
          end

          if xml_element
            render_xml_element(xml, xml_element, original_model, options)
          else
            render_legacy_model(xml, options)
          end
        end

        # Build XML from XmlDataModel::XmlElement structure with a declaration plan
        #
        # @param builder [Builder] XML builder
        # @param xml_element [XmlDataModel::XmlElement] root element
        # @param plan [DeclarationPlan] the declaration plan
        # @param options [Hash] serialization options
        def build_xml_element_with_plan(builder, xml_element, plan,
    options = {})
          # Add processing instructions before the root element
          if xml_element.is_a?(Lutaml::Xml::DataModel::XmlElement)
            xml_element.processing_instructions.each do |pi|
              builder.add_processing_instruction(pi.target, pi.content)
            end
          end

          build_plan_node(builder, xml_element, plan.root_node, plan: plan,
                                                                options: options)
        end

        private

        def standalone_value(value)
          case value
          when true then "yes"
          when false then "no"
          else value.to_s
          end
        end

        def transformable_xml_element(options)
          return root if root.is_a?(Lutaml::Xml::DataModel::XmlElement)

          mapper_class = options[:mapper_class] || root.class
          xml_mapping = mapper_class.mappings_for(:xml)

          return nil if xml_mapping.raw_mapping&.custom_methods&.[](:to)

          yield(root)
          mapper_class.transformation_for(:xml, register).transform(root,
                                                                    options)
        end

        def render_xml_element(xml, xml_element, original_model, options)
          mapper_class = options[:mapper_class] || xml_element.class
          mapping = mapper_class.mappings_for(:xml)
          plan = declaration_plan_for(
            xml_element,
            mapping,
            options_with_original_namespace_data(options, original_model,
                                                 xml_element),
            mapper_class,
          )

          render_options = options.merge(is_root_element: true)
          render_options[:original_model] = original_model if original_model
          build_xml_element_with_plan(xml, xml_element, plan, render_options)
        end

        def render_legacy_model(xml, options)
          mapper_class = options[:mapper_class] || root.class
          xml_mapping = mapper_class.mappings_for(:xml)
          plan = declaration_plan_for(root, xml_mapping, options, mapper_class)

          build_element_with_plan(xml, root, plan, options)
        end

        def declaration_plan_for(element, mapping, options, mapper_class)
          needs = NamespaceCollector.new(register).collect(
            element, mapping, mapper_class: mapper_class
          )
          DeclarationPlanner.new(register).plan(element, mapping, needs,
                                                options: options)
        end

        def options_with_original_namespace_data(options, original_model,
    xml_element)
          original_ns_uris = {}
          stored_plan = nil

          if original_model
            mapping_for_original = options[:mapper_class]&.mappings_for(:xml) ||
              original_model.class.mappings_for(:xml)
            original_ns_uris = collect_original_namespace_uris(
              original_model, mapping_for_original
            )
            if original_model.is_a?(Lutaml::Model::Serialize)
              stored_plan = original_model.import_declaration_plan
            end
          elsif xml_element.is_a?(Lutaml::Xml::DataModel::XmlElement)
            original_ns_uri = xml_element.original_namespace_uri
            if original_ns_uri
              mapper_class = options[:mapper_class] || xml_element.class
              xml_mapping = begin
                mapper_class.mappings_for(:xml)
              rescue StandardError
                nil
              end
              if xml_mapping&.namespace_class
                canonical_uri = xml_mapping.namespace_class.uri
                if canonical_uri != original_ns_uri
                  original_ns_uris[canonical_uri] =
                    original_ns_uri
                end
              end
            end
          end

          options_with_original_ns = options.merge(
            __original_namespace_uris: original_ns_uris,
          )
          if stored_plan
            options_with_original_ns[:stored_xml_declaration_plan] =
              stored_plan
          end
          options_with_original_ns
        end

        def text_content_for_xml(value)
          ::Moxml.preprocess_entities(value.to_s)
        end

        def build_plan_node(xml, xml_element, element_node, plan: nil,
    options: {}, previous_sibling_had_xmlns_blank: false)
          qualified_name = element_node.qualified_name
          attributes = {}

          original_ns_uris = plan&.original_namespace_uris || {}
          element_node.hoisted_declarations.sort_by do |prefix, _uri|
            prefix.nil? ? "" : prefix.to_s
          end.each do |key, uri|
            next if uri == "http://www.w3.org/XML/1998/namespace"

            effective_uri = if self.class.fpi?(uri)
                              self.class.fpi_to_urn(uri)
                            else
                              original_ns_uris[uri] || uri
                            end

            xmlns_name = key ? "xmlns:#{key}" : "xmlns"
            attributes[xmlns_name] = effective_uri
          end

          xml_element.attributes.each_with_index do |xml_attr, idx|
            attr_node = element_node.attribute_nodes[idx]
            attributes[attr_node.qualified_name] = xml_attr.value.to_s
          end

          if xml_element.is_a?(Lutaml::Xml::DataModel::XmlElement) && xml_element.xsi_nil
            attributes["xsi:nil"] = "true"
          end

          attributes.merge!(element_node.schema_location_attr) if element_node.schema_location_attr
          needs_xmlns_blank = element_node.needs_xmlns_blank &&
            (options[:pretty] ? !previous_sibling_had_xmlns_blank : true)
          attributes["xmlns"] = "" if needs_xmlns_blank

          xml.create_and_add_element(qualified_name, attributes: attributes) do
            if xml_element.is_a?(Lutaml::Xml::DataModel::XmlElement)
              raw_content = xml_element.raw_content
              if raw_content && !raw_content.to_s.empty?
                xml.add_xml_fragment(xml, raw_content.to_s)
                return
              end
            end

            child_element_index = 0
            previous_child_had_xmlns_blank = false
            xml_element.children.each do |xml_child|
              case xml_child
              when Lutaml::Xml::DataModel::XmlElement
                child_node = element_node.element_nodes[child_element_index]
                child_element_index += 1

                build_plan_node(
                  xml,
                  xml_child,
                  child_node,
                  plan: plan,
                  options: options,
                  previous_sibling_had_xmlns_blank: previous_child_had_xmlns_blank,
                )
                previous_child_had_xmlns_blank ||= child_node.needs_xmlns_blank
              when Lutaml::Xml::DataModel::XmlComment
                xml.add_comment(xml_child.content)
              when Lutaml::Xml::DataModel::XmlRawFragment
                xml.add_xml_fragment(xml, xml_child.content)
              when String
                if xml_element.cdata
                  xml.cdata(xml_child.to_s)
                else
                  xml.text(text_content_for_xml(xml_child))
                end
              end
            end

            if xml_element.text_content
              if xml_element.cdata
                xml.cdata(xml_element.text_content.to_s)
              else
                xml.text(text_content_for_xml(xml_element.text_content))
              end
            end
          end
        end
      end
    end
  end
end
