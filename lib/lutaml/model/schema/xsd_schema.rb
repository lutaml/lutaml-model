require_relative "schema_builder"

module Lutaml
  module Model
    module Schema
      class XsdSchema
        extend SharedMethods

        def self.generate(klass, options = {})
          register = extract_register_from(klass)
          xml_mapping = klass.mappings_for(:xml)

          # Use SchemaBuilder with adapter from options or config
          adapter_type = options[:adapter] || Config.xml_adapter_type || :nokogiri

          schema_builder = SchemaBuilder.new(
            adapter_type: adapter_type,
            options: { encoding: "UTF-8" }
          ) do |xml|
            generate_schema(xml, klass, xml_mapping, register, options)
          end

          schema_builder.to_xml(options)
        end

        def self.generate_schema(xml, klass, xml_mapping, register, options)
          schema_attrs = { xmlns: "http://www.w3.org/2001/XMLSchema" }

          # Add namespace metadata from XmlNamespace class if present
          if xml_mapping.namespace_class
            ns = xml_mapping.namespace_class
            schema_attrs[:targetNamespace] = ns.uri
            schema_attrs[:elementFormDefault] = ns.element_form_default.to_s
            schema_attrs[:attributeFormDefault] = ns.attribute_form_default.to_s
            schema_attrs[:version] = ns.version if ns.version

            # Add xmlns declarations for the target namespace
            prefix = xml_mapping.namespace_prefix || ns.prefix_default
            if prefix && !prefix.empty?
              schema_attrs["xmlns:#{prefix}".to_sym] = ns.uri
            end
          elsif xml_mapping.namespace_uri
            # Legacy: namespace URI without XmlNamespace class
            schema_attrs[:targetNamespace] = xml_mapping.namespace_uri
            schema_attrs[:elementFormDefault] = "unqualified"
            schema_attrs[:attributeFormDefault] = "unqualified"

            if xml_mapping.namespace_prefix
              schema_attrs["xmlns:#{xml_mapping.namespace_prefix}".to_sym] = xml_mapping.namespace_uri
            end
          end

          xml.schema(schema_attrs) do
            # Generate imports from XmlNamespace
            if xml_mapping.namespace_class
              generate_imports(xml, xml_mapping.namespace_class)
              generate_includes(xml, xml_mapping.namespace_class)
            end

            # Generate annotation if present
            if xml_mapping.documentation_text || xml_mapping.namespace_class&.documentation
              generate_annotation(xml, xml_mapping)
            end

            # Determine element name for XSD
            # If there's an explicit element declaration, use that
            # If there's an explicit XML mapping with root, use that
            # Otherwise use full class name (not the default mapping's root)
            if has_explicit_xml_mapping?(klass, xml_mapping)
              # Explicit XML mapping defined by user
              if xml_mapping.element_name
                element_name = xml_mapping.element_name
              elsif xml_mapping.root_element
                element_name = xml_mapping.root_element
              else
                element_name = klass.name
              end
            else
              # No explicit mapping - use full class name
              element_name = klass.name
            end

            # Generate element wrapper with inline complexType
            # This maintains backward compatibility with existing tests
            xml.element(name: element_name) do
              generate_complex_type_content(xml, klass, register, xml_mapping)
            end
          end
        end

        def self.generate_imports(xml, namespace_class)
          return unless namespace_class.imports&.any?

          namespace_class.imports.each do |imported_ns|
            import_attrs = { namespace: imported_ns.uri }
            import_attrs[:schemaLocation] = imported_ns.schema_location if imported_ns.schema_location
            xml.import(import_attrs)
          end
        end

        def self.generate_includes(xml, namespace_class)
          return unless namespace_class.includes&.any?

          namespace_class.includes.each do |schema_location|
            xml.include(schemaLocation: schema_location)
          end
        end

        def self.generate_annotation(xml, xml_mapping)
          xml.annotation do
            doc_text = xml_mapping.documentation_text
            doc_text ||= xml_mapping.namespace_class&.documentation if xml_mapping.namespace_class

            xml.documentation(doc_text) if doc_text
          end
        end

        def self.generate_complex_type_content(xml, klass, register, xml_mapping)
          xml.complexType do
            if klass.attributes.any?
              xml.sequence do
                generate_elements(xml, klass, register, xml_mapping)
              end
            end
            generate_attributes(xml, klass, register, xml_mapping) if xml_mapping
          end
        end

        def self.generate_complex_type(xml, klass, type_name, register, xml_mapping = nil)
          xml.complexType(name: type_name) do
            if klass.attributes.any?
              xml.sequence do
                generate_elements(xml, klass, register, xml_mapping)
              end
            end
            generate_attributes(xml, klass, register, xml_mapping)
          end
        end

        def self.generate_elements(xml, klass, register, xml_mapping)
          klass.attributes.each do |name, attr|
            next if xml_mapping && attr_is_xml_attribute?(xml_mapping, name)

            attr_type = attr.type(register)

            if attr_type <= Lutaml::Model::Serialize
              # Nested model - generate inline complexType
              if attr.collection?
                # Collection of models - special handling
                element_attrs = { name: name.to_s }
                element_attrs[:minOccurs] = "0"
                element_attrs[:maxOccurs] = "unbounded"

                xml.element(element_attrs) do
                  xml.complexType do
                    xml.sequence do
                      xml.element(name: "item", type: get_xsd_type(attr_type))
                    end
                  end
                end
              else
                # Single nested model
                xml.element(name: name.to_s) do
                  generate_complex_type_content(xml, attr_type, register, nil)
                end
              end
            else
              # Value type
              xsd_type = get_attribute_xsd_type(attr, attr_type, register)

              if attr.collection?
                # Collection of simple types
                element_attrs = { name: name.to_s }
                element_attrs[:minOccurs] = "0"
                element_attrs[:maxOccurs] = "unbounded"

                xml.element(element_attrs) do
                  xml.complexType do
                    xml.sequence do
                      xml.element(name: "item", type: xsd_type)
                    end
                  end
                end
              else
                # Simple element
                element_attrs = build_element_attributes(name, xsd_type, attr, xml_mapping, name)
                xml.element(element_attrs)
              end
            end
          end
        end

        def self.generate_attributes(xml, klass, register, xml_mapping)
          return unless xml_mapping

          xml_mapping.attributes.each do |rule|
            attr = klass.attributes[rule.to]
            next unless attr

            attr_type = attr.type(register)
            xsd_type = get_attribute_xsd_type(attr, attr_type, register)

            attr_attrs = { name: rule.name, type: xsd_type }
            attr_attrs[:use] = "required" if attr.options[:required]

            # Add form attribute if specified
            if rule.form
              attr_attrs[:form] = rule.form.to_s
            end

            # Add documentation if present
            if rule.documentation
              xml.attribute(attr_attrs) do
                xml.annotation do
                  xml.documentation(rule.documentation)
                end
              end
            else
              xml.attribute(attr_attrs)
            end
          end
        end

        def self.attr_is_xml_attribute?(xml_mapping, attr_name)
          xml_mapping.attributes.any? { |rule| rule.to == attr_name }
        end

        def self.build_element_attributes(name, xsd_type, attr, xml_mapping, attr_name)
          attrs = { name: name.to_s, type: xsd_type }

          # Handle collection cardinality
          if attr.collection?
            range = attr.resolved_collection
            if range
              attrs[:minOccurs] = range.min.to_s
              attrs[:maxOccurs] = range.end.infinite? ? "unbounded" : range.max.to_s
            else
              attrs[:minOccurs] = "0"
              attrs[:maxOccurs] = "unbounded"
            end
          elsif attr.options[:required]
            # Required attribute - no minOccurs needed (defaults to 1)
          else
            # Optional attribute - only add minOccurs if explicitly optional
            # For backward compatibility, don't add minOccurs="0" by default
          end

          # Add form attribute from mapping rule if present
          if xml_mapping
            rule = xml_mapping.find_element(attr_name)
            attrs[:form] = rule.form.to_s if rule&.form

            # Add documentation if present
            if rule&.documentation
              attrs[:annotation] = rule.documentation
            end
          end

          attrs
        end

        def self.has_explicit_xml_mapping?(klass, xml_mapping)
          # A mapping is considered explicit if the user defined an `xml do` block
          # Auto-generated default mappings have:
          # - root_element equal to Utils.base_class_name (without module prefix)
          # - Elements auto-generated for each attribute

          # If no root element, it's not auto-generated (could be no_root)
          return true unless xml_mapping.root_element

          # Compare root element with base class name
          # Auto-generated uses base_class_name, explicit may use full name or custom
          base_name = Utils.base_class_name(klass)
          xml_mapping.root_element != base_name
        end

        def self.get_attribute_xsd_type(attr, attr_type, register)
          # Priority: explicit xsd_type > type.xsd_type() > default mapping

          # 1. Check for explicit xsd_type override
          return attr.options[:xsd_type] if attr.options[:xsd_type]

          # 2. Check if type has xsd_type method
          if attr_type.respond_to?(:xsd_type)
            # Special handling for Reference type
            if attr_type == Lutaml::Model::Type::Reference
              # Check if target attribute uses xs:ID
              target_xsd_type = get_target_xsd_type(attr, register)
              return attr_type.xsd_type(target_xsd_type)
            end

            return attr_type.xsd_type
          end

          # 3. Fall back to default mapping
          get_xsd_type(attr_type)
        end

        def self.get_target_xsd_type(attr, register)
          return nil unless attr.options[:ref_model_class]
          return nil unless attr.options[:ref_key_attribute]

          begin
            model_class = Object.const_get(attr.options[:ref_model_class])
            target_attr = model_class.attributes[attr.options[:ref_key_attribute]]
            return nil unless target_attr

            target_type = target_attr.type(register)
            get_attribute_xsd_type(target_attr, target_type, register)
          rescue NameError
            nil
          end
        end

        def self.get_xsd_type(type)
          {
            Lutaml::Model::Type::String => "xs:string",
            Lutaml::Model::Type::Integer => "xs:integer",
            Lutaml::Model::Type::Boolean => "xs:boolean",
            Lutaml::Model::Type::Float => "xs:float",
            Lutaml::Model::Type::Decimal => "xs:decimal",
            Lutaml::Model::Type::Date => "xs:date",
            Lutaml::Model::Type::Time => "xs:time",
            Lutaml::Model::Type::DateTime => "xs:dateTime",
            Lutaml::Model::Type::TimeWithoutDate => "xs:time",
            Lutaml::Model::Type::Duration => "xs:duration",
            Lutaml::Model::Type::Uri => "xs:anyURI",
            Lutaml::Model::Type::QName => "xs:QName",
            Lutaml::Model::Type::Base64Binary => "xs:base64Binary",
            Lutaml::Model::Type::HexBinary => "xs:hexBinary",
            Lutaml::Model::Type::Hash => "xs:anyType",
            Lutaml::Model::Type::Symbol => "xs:string",
          }[type] || "xs:string" # Default to string for unknown types
        end
      end
    end
  end
end
