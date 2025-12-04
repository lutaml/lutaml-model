require_relative "schema_builder"
require_relative "xs_builtin_types"

module Lutaml
  module Model
    module Schema
      class XsdSchema
        extend SharedMethods

        def self.generate(klass, options = {})
          register = extract_register_from(klass)
          xml_mapping = klass.mappings_for(:xml)

          # Validate XSD types unless explicitly skipped
          validate_xsd_types!(klass, register) unless options[:skip_validation]

          # Use SchemaBuilder with adapter from options or config
          adapter_type = options[:adapter] || Config.xml_adapter_type || :nokogiri

          schema_builder = SchemaBuilder.new(
            adapter_type: adapter_type,
            options: { encoding: "UTF-8" },
          ) do |xml|
            generate_schema(xml, klass, xml_mapping, register, options)
          end

          schema_builder.to_xml(options)
        end

        # Classify an XSD type name into one of three categories
        #
        # @param type_name [String] The XSD type name to classify
        # @param klass [Class] The model class being processed
        # @param register [Register] The register for type resolution
        # @return [Symbol] :builtin, :custom, :unresolvable, or :unknown
        def self.classify_xsd_type(type_name, klass, register)
          return :builtin if XsBuiltinTypes.builtin?(type_name)

          # Custom type - check if resolvable
          if type_name && !type_name.start_with?("xs:")
            return :custom if type_resolvable?(type_name, klass, register)

            return :unresolvable
          end

          :unknown
        end

        # Check if a custom XSD type can be resolved in the model hierarchy
        #
        # @param type_name [String] The custom type name to resolve
        # @param klass [Class] The model class being processed
        # @param register [Register] The register for type resolution
        # @return [Boolean] true if the type can be resolved
        def self.type_resolvable?(type_name, klass, register)
          # Search in nested model attributes
          klass.attributes.each_value do |attr|
            attr_type = attr.type(register)
            next unless attr_type <= Lutaml::Model::Serialize

            nested_mapping = attr_type.mappings_for(:xml)
            return true if nested_mapping&.type_name_value == type_name
          end

          # Could be extended in the future to search in:
          # - Register for custom Type::Value classes with matching xsd_type
          # - Global namespace registry
          # - External schema imports

          false
        end

        # Validate all XSD types referenced by the model
        #
        # @param klass [Class] The model class to validate
        # @param register [Register] The register for type resolution
        # @raise [UnresolvableTypeError] if any types cannot be resolved
        def self.validate_xsd_types!(klass, register)
          errors = []

          klass.attributes.each do |name, attr|
            attr_type = attr.type(register)

            # Validate Type::Value xsd_type
            if attr_type.respond_to?(:xsd_type)
              type_name = attr_type.xsd_type
              classification = classify_xsd_type(type_name, klass, register)

              if classification == :unresolvable
                errors << "Attribute '#{name}' uses unresolvable xsd_type '#{type_name}'. " \
                          "Custom types must be defined as LutaML Type::Value or Model classes."
              end
            end

            # Recursively validate nested models
            if attr_type <= Lutaml::Model::Serialize
              begin
                validate_xsd_types!(attr_type, register)
              rescue UnresolvableTypeError => e
                errors << "In nested model #{attr_type.name}: #{e.message}"
              end
            end
          end

          raise UnresolvableTypeError, errors.join("\n") if errors.any?
        end

        def self.generate_schema(xml, klass, xml_mapping, register, _options)
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
              schema_attrs[:"xmlns:#{prefix}"] = ns.uri
            end
          elsif xml_mapping.namespace_uri
            # Legacy: namespace URI without XmlNamespace class
            schema_attrs[:targetNamespace] = xml_mapping.namespace_uri
            schema_attrs[:elementFormDefault] = "unqualified"
            schema_attrs[:attributeFormDefault] = "unqualified"

            if xml_mapping.namespace_prefix
              schema_attrs[:"xmlns:#{xml_mapping.namespace_prefix}"] =
                xml_mapping.namespace_uri
            end
          end

          xml.schema(schema_attrs) do
            # Generate imports from XmlNamespace
            if xml_mapping.namespace_class
              generate_imports(xml, xml_mapping.namespace_class)
              generate_includes(xml, xml_mapping.namespace_class)
            end

            # Generate imports for Type namespaces
            type_namespaces = collect_type_namespaces(klass, register)
            type_namespaces.each do |ns_class|
              # Only import if different from target namespace
              next if ns_class.uri == schema_attrs[:targetNamespace]

              import_attrs = { namespace: ns_class.uri }
              if ns_class.schema_location
                import_attrs[:schemaLocation] = ns_class.schema_location
              end
              xml.import(import_attrs)
            end

            # Generate annotation if present
            if xml_mapping.documentation_text || xml_mapping.namespace_class&.documentation
              generate_annotation(xml, xml_mapping)
            end

            # Determine element name and type name for XSD pattern selection
            element_name = if has_explicit_xml_mapping?(klass, xml_mapping)
                             xml_mapping.element_name || xml_mapping.root_element
                           else
                             nil
                           end

            type_name = xml_mapping.type_name_value

            # Generate XSD based on three patterns:
            # Pattern 1: element only -> inline anonymous complexType
            # Pattern 2: type_name only -> named complexType (no element)
            # Pattern 3: both element and type_name -> element + named complexType

            if element_name && type_name
              # Pattern 3: Both element and named type
              xml.element(name: element_name, type: type_name)
              generate_complex_type(xml, klass, type_name, register, xml_mapping)
            elsif type_name && !element_name
              # Pattern 2: Type-only (no element)
              generate_complex_type(xml, klass, type_name, register, xml_mapping)
            else
              # Pattern 1: Anonymous inline (element with no type_name)
              # Use class name as fallback element name if not specified
              elem_name = element_name || klass.name
              xml.element(name: elem_name) do
                generate_complex_type_content(xml, klass, register, xml_mapping)
              end
            end

            # Generate type definitions for nested models with type_name
            generate_nested_type_definitions(xml, klass, register)
          end
        end

        def self.generate_imports(xml, namespace_class)
          return unless namespace_class.imports&.any?

          namespace_class.imports.each do |imported_ns|
            import_attrs = { namespace: imported_ns.uri }
            if imported_ns.schema_location
              import_attrs[:schemaLocation] =
                imported_ns.schema_location
            end
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

        def self.generate_nested_type_definitions(xml, klass, register)
          klass.attributes.each_value do |attr|
            attr_type = attr.type(register)
            next unless attr_type <= Lutaml::Model::Serialize

            nested_mapping = attr_type.mappings_for(:xml)
            nested_type_name = nested_mapping&.type_name_value

            # Generate type definition if nested model has type_name
            if nested_type_name
              generate_complex_type(xml, attr_type, nested_type_name, register, nested_mapping)
              # Recursively generate nested types
              generate_nested_type_definitions(xml, attr_type, register)
            end
          end
        end

        def self.generate_complex_type_content(xml, klass, register,
xml_mapping)
          xml.complexType do
            if klass.attributes.any?
              xml.sequence do
                generate_elements(xml, klass, register, xml_mapping)
              end
            end
            if xml_mapping
              generate_attributes(xml, klass, register,
                                  xml_mapping)
            end
          end
        end

        def self.generate_complex_type(xml, klass, type_name, register,
xml_mapping = nil)
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

            # Find the mapping rule for this attribute
            mapping_rule = xml_mapping&.find_element(name)

            attr_type = attr.type(register)

            if attr_type <= Lutaml::Model::Serialize
              # Nested model - check if it has a type_name for reference
              nested_mapping = attr_type.mappings_for(:xml)
              nested_type_name = nested_mapping&.type_name_value

              if attr.collection?
                # Collection of models
                element_attrs = { name: name.to_s }
                element_attrs[:minOccurs] = "0"
                element_attrs[:maxOccurs] = "unbounded"

                if nested_type_name
                  # Reference named type
                  element_attrs[:type] = nested_type_name
                  xml.element(element_attrs)
                else
                  # Inline anonymous complexType
                  xml.element(element_attrs) do
                    xml.complexType do
                      xml.sequence do
                        xml.element(name: "item", type: get_xsd_type(attr_type))
                      end
                    end
                  end
                end
              else
                # Single nested model
                if nested_type_name
                  # Reference named type
                  xml.element(name: name.to_s, type: nested_type_name)
                else
                  # Inline anonymous complexType
                  xml.element(name: name.to_s) do
                    generate_complex_type_content(xml, attr_type, register, nil)
                  end
                end
              end
            else
              # Value type
              xsd_type = get_attribute_xsd_type(attr, attr_type, register, mapping_rule)

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
                element_attrs = build_element_attributes(name, xsd_type, attr,
                                                         xml_mapping, name)
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
            xsd_type = get_attribute_xsd_type(attr, attr_type, register, rule)

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

        def self.build_element_attributes(name, xsd_type, attr, xml_mapping,
attr_name)
          attrs = { name: name.to_s, type: xsd_type }

          # Handle collection cardinality
          if attr.collection?
            range = attr.resolved_collection
            if range
              attrs[:minOccurs] = range.min.to_s
              attrs[:maxOccurs] =
                range.end.infinite? ? "unbounded" : range.max.to_s
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

        def self.get_attribute_xsd_type(attr, attr_type, register, mapping_rule = nil)
          # Priority:
          # 1. Attribute-level xsd_type (deprecated but still supported)
          # 2. Type-level xsd_type (from Type class)
          # 3. Default mapping

          # 1. Check for deprecated attribute-level xsd_type override
          return attr.options[:xsd_type] if attr.options[:xsd_type]

          # 2. Check if type has xsd_type method (Type-level)
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

        def self.collect_type_namespaces(klass, register)
          require "set"
          namespaces = Set.new

          klass.attributes.each_value do |attr|
            type_class = attr.type(register)
            next unless type_class

            # Get Type::Value namespace
            if type_class.respond_to?(:xml_namespace) && type_class.xml_namespace
              namespaces << type_class.xml_namespace
            end

            # Get Model namespace
            if type_class <= Lutaml::Model::Serialize &&
                type_class.respond_to?(:namespace) && type_class.namespace
              namespaces << type_class.namespace
            end
          end

          namespaces.to_a
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
