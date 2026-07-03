# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      # XSD Schema generation for XML models
      #
      # Generates W3C XML Schema (XSD) from LutaML model classes.
      # Supports namespace declarations, type definitions, and nested models.
      class XsdSchema
        # Include shared methods from model schema
        include Lutaml::Model::Schema::SharedMethods
        extend Lutaml::Model::Schema::SharedMethods

        # The XSD vocabulary namespace, routed through the project's namespace
        # object so the declared prefix and every emitted prefix stay in sync.
        # W3c::XsNamespace binds "xs" (matching the built-in xs:-prefixed type
        # references) and opts out of the W3C-reserved-prefix warning.
        def self.xsd_ns
          @xsd_ns ||= Lutaml::Xml::W3c::XsNamespace.new
        end

        # Qualify an XSD structure element name with the bound prefix, so the
        # prefix used on emitted elements always matches the declared xmlns.
        def self.qn(local)
          "#{xsd_ns.prefix}:#{local}"
        end

        # The prefix of the schema's target namespace, or nil when the schema
        # has no target namespace (named types then live in no-namespace and
        # their references stay unprefixed). Never returns the reserved "xs".
        def self.target_ns_prefix(xml_mapping)
          prefix =
            if xml_mapping&.namespace_class
              xml_mapping.namespace_prefix ||
                xml_mapping.namespace_class.prefix_default
            elsif xml_mapping&.namespace_uri
              xml_mapping.namespace_prefix
            end
          return if prefix.nil? || prefix.empty? || prefix == xsd_ns.prefix

          prefix
        end

        # Qualify a named-type reference with the target-namespace prefix so it
        # resolves to the namespace the type is defined in. Built-in refs (which
        # already carry a prefix, e.g. "xs:string") and no-namespace schemas
        # (prefix nil) are returned unchanged.
        def self.qualify_type_ref(type_name, prefix)
          return type_name if prefix.nil? || type_name.nil?
          return type_name if type_name.include?(":")

          "#{prefix}:#{type_name}"
        end

        # The prefix a named-type reference should carry: the referenced model's
        # own namespace prefix when it has one (the type lives in that
        # namespace), otherwise the schema's target prefix.
        def self.nested_ref_prefix(nested_mapping, target_prefix)
          prefix = nested_mapping&.namespace_class&.prefix_default
          return target_prefix if prefix.nil? || prefix.empty? ||
            prefix == xsd_ns.prefix

          prefix
        end

        def self.generate(klass, options = {})
          register = extract_register_from(klass)
          xml_mapping = klass.mappings_for(:xml)

          # Validate XSD types unless explicitly skipped
          validate_xsd_types!(klass, register) unless options[:skip_validation]

          # Use Builder with adapter from options or config
          adapter_type = options[:adapter] || Lutaml::Model::Config.xml_adapter_type || :nokogiri

          schema_builder = Builder.new(
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
          return :builtin if BuiltinTypes.builtin?(type_name)

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

          false
        end

        # Validate all XSD types referenced by the model
        #
        # @param klass [Class] The model class to validate
        # @param register [Register] The register for type resolution
        # @raise [UnresolvableTypeError] if any types cannot be resolved
        def self.validate_xsd_types!(klass, register, seen = Set.new)
          # Cycle guard: recursive models (A -> B -> A) would otherwise recurse
          # forever. A class already being validated needs no re-validation.
          return unless seen.add?(klass)

          errors = []

          klass.attributes.each do |name, attr|
            attr_type = attr.type(register)

            # Validate Type::Value xsd_type
            if attr_type.is_a?(Class) && attr_type < Lutaml::Model::Type::Value
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
                validate_xsd_types!(attr_type, register, seen)
              rescue Lutaml::Model::UnresolvableTypeError => e
                errors << "In nested model #{attr_type.name}: #{e.message}"
              end
            end
          end

          if errors.any?
            raise Lutaml::Model::UnresolvableTypeError,
                  errors.join("\n")
          end
        end

        def self.generate_schema(xml, klass, xml_mapping, register, _options)
          # Bind the XSD vocabulary namespace to the "xs" prefix (via the
          # namespace object, not a hardcoded string) so the xs:-prefixed type
          # references and the prefixed structure elements are both declared.
          schema_attrs = { xsd_ns.attr_name.to_sym => xsd_ns.uri }

          # Add namespace metadata from XmlNamespace class if present
          if xml_mapping.namespace_class
            ns = xml_mapping.namespace_class
            schema_attrs[:targetNamespace] = ns.uri
            schema_attrs[:elementFormDefault] = ns.element_form_default.to_s
            schema_attrs[:attributeFormDefault] = ns.attribute_form_default.to_s
            schema_attrs[:version] = ns.version if ns.version

            # Add xmlns declarations for the target namespace, but never rebind
            # the reserved "xs" prefix already bound to the XSD namespace.
            prefix = xml_mapping.namespace_prefix || ns.prefix_default
            if prefix && !prefix.empty? && prefix != xsd_ns.prefix
              schema_attrs[:"xmlns:#{prefix}"] = ns.uri
            end
          elsif xml_mapping.namespace_uri
            # Legacy: namespace URI without XmlNamespace class
            schema_attrs[:targetNamespace] = xml_mapping.namespace_uri
            schema_attrs[:elementFormDefault] = "unqualified"
            schema_attrs[:attributeFormDefault] = "unqualified"

            if xml_mapping.namespace_prefix &&
                xml_mapping.namespace_prefix != xsd_ns.prefix
              schema_attrs[:"xmlns:#{xml_mapping.namespace_prefix}"] =
                xml_mapping.namespace_uri
            end
          end

          # Named-type references are qualified with the namespace prefix of the
          # namespace the type is defined in.
          target_prefix = target_ns_prefix(xml_mapping)
          target_uri = schema_attrs[:targetNamespace]

          # A target namespace referenced by named-type QNames needs a usable
          # prefix; synthesise one when the namespace class declares none.
          if target_uri && (target_prefix.nil? || target_prefix.empty?)
            target_prefix = "tns"
            schema_attrs[:"xmlns:#{target_prefix}"] ||= target_uri
          end

          # Declare every namespace class used anywhere in the tree on the root
          # <xs:schema>, deduped by class, so foreign type references resolve.
          # A prefix bound to two different namespaces is unresolvable -> raise.
          tree_ns_classes = collect_namespace_classes(klass, register)
          tree_ns_classes.each do |ns_class|
            prefix = ns_class.prefix_default
            unusable = prefix.nil? || prefix.empty? || prefix == xsd_ns.prefix

            # A foreign namespace is referenced by a prefixed QName, so it must
            # have a usable prefix of its own — it cannot borrow the target's.
            if unusable && ns_class.uri != target_uri
              raise Lutaml::Model::Error,
                    "XSD generation: foreign namespace '#{ns_class.uri}' needs " \
                    "a usable prefix_default (not nil/empty/'xs') to be " \
                    "referenced from the '#{target_uri}' schema."
            end
            next if unusable

            key = :"xmlns:#{prefix}"
            existing = schema_attrs[key]
            if existing && existing != ns_class.uri
              raise Lutaml::Model::Error,
                    "XSD generation: namespace prefix '#{prefix}' is bound to " \
                    "two different namespaces (#{existing} and #{ns_class.uri}). " \
                    "Give them distinct prefixes."
            end
            schema_attrs[key] = ns_class.uri
          end

          xml.public_send(qn("schema"), schema_attrs) do
            # Explicit imports declared on the root's XmlNamespace class.
            imported_uris = Set.new
            if xml_mapping.namespace_class
              imported_uris = generate_imports(xml, xml_mapping.namespace_class)
              generate_includes(xml, xml_mapping.namespace_class)
            end

            # Import every foreign namespace referenced by the tree (any
            # namespace other than this schema's own target), deduped by URI.
            # Foreign types are defined in their own schema, not here.
            tree_ns_classes.each do |ns_class|
              next if ns_class.uri == target_uri
              next unless imported_uris.add?(ns_class.uri)

              import_attrs = { namespace: ns_class.uri }
              if ns_class.schema_location
                import_attrs[:schemaLocation] = ns_class.schema_location
              end
              xml.public_send(qn("import"), import_attrs)
            end

            # Generate annotation if present
            if xml_mapping.documentation_text || xml_mapping.namespace_class&.documentation
              generate_annotation(xml, xml_mapping)
            end

            # Determine element name and type name for XSD pattern selection
            element_name = if has_explicit_xml_mapping?(klass, xml_mapping)
                             xml_mapping.element_name || xml_mapping.root_element
                           end

            type_name = xml_mapping.type_name_value

            # Generate XSD based on three patterns:
            # Pattern 1: element only -> inline anonymous complexType
            # Pattern 2: type_name only -> named complexType (no element)
            # Pattern 3: both element and type_name -> element + named complexType

            if element_name && type_name
              # Pattern 3: Both element and named type
              xml.public_send(qn("element"),
                              { name: element_name,
                                type: qualify_type_ref(type_name, target_prefix) })
              generate_complex_type(xml, klass, type_name, register,
                                    xml_mapping, target_prefix: target_prefix)
            elsif type_name && !element_name
              # Pattern 2: Type-only (no element)
              generate_complex_type(xml, klass, type_name, register,
                                    xml_mapping, target_prefix: target_prefix)
            else
              # Pattern 1: Anonymous inline (element with no type_name)
              # Use class name as fallback element name if not specified
              elem_name = element_name || klass.name
              xml.public_send(qn("element"), { name: elem_name }) do
                generate_complex_type_content(xml, klass, register, xml_mapping,
                                              target_prefix: target_prefix)
              end
            end

            # Generate type definitions for nested models with type_name
            generate_nested_type_definitions(xml, klass, register,
                                             target_prefix: target_prefix,
                                             target_uri: target_uri)
          end
        end

        # Emit <xs:import> for each namespace the root's XmlNamespace class
        # explicitly declares. Returns the Set of imported URIs so the tree
        # import loop can dedupe against them.
        def self.generate_imports(xml, namespace_class)
          imported = Set.new
          return imported unless namespace_class.imports&.any?

          namespace_class.imports.each do |imported_ns|
            next unless imported.add?(imported_ns.uri)

            import_attrs = { namespace: imported_ns.uri }
            if imported_ns.schema_location
              import_attrs[:schemaLocation] =
                imported_ns.schema_location
            end
            xml.public_send(qn("import"), import_attrs)
          end

          imported
        end

        def self.generate_includes(xml, namespace_class)
          return unless namespace_class.includes&.any?

          namespace_class.includes.each do |schema_location|
            xml.public_send(qn("include"), { schemaLocation: schema_location })
          end
        end

        def self.generate_annotation(xml, xml_mapping)
          xml.public_send(qn("annotation")) do
            doc_text = xml_mapping.documentation_text
            doc_text ||= xml_mapping.namespace_class&.documentation if xml_mapping.namespace_class

            xml.public_send(qn("documentation"), doc_text) if doc_text
          end
        end

        def self.generate_nested_type_definitions(xml, klass, register,
target_prefix: nil, target_uri: nil, seen: nil)
          # Cycle guard, seeded with the root class (already defined by
          # generate_schema) so it is never redefined via a back-reference.
          seen ||= Set[klass]

          klass.attributes.each_value do |attr|
            attr_type = attr.type(register)
            next unless attr_type <= Lutaml::Model::Serialize
            next unless seen.add?(attr_type)

            nested_mapping = attr_type.mappings_for(:xml)
            nested_type_name = nested_mapping&.type_name_value

            # Define a named type only when it belongs to this schema's target
            # namespace; a foreign type is imported, not defined here. Recurse
            # regardless — a same-target type can be nested under a foreign model.
            if nested_type_name &&
                !foreign_namespace?(nested_mapping, target_uri)
              generate_complex_type(xml, attr_type, nested_type_name, register,
                                    nested_mapping, target_prefix: target_prefix)
            end

            generate_nested_type_definitions(xml, attr_type, register,
                                             target_prefix: target_prefix,
                                             target_uri: target_uri, seen: seen)
          end
        end

        # Whether a nested model's mapping belongs to a namespace other than the
        # schema's target namespace. A model with no namespace belongs to the
        # target schema (not foreign).
        def self.foreign_namespace?(mapping, target_uri)
          ns_class = mapping&.namespace_class
          return false unless ns_class

          ns_class.uri != target_uri
        end

        def self.generate_complex_type_content(xml, klass, register,
xml_mapping, target_prefix: nil)
          xml.public_send(qn("complexType")) do
            if klass.attributes.any?
              xml.public_send(qn("sequence")) do
                generate_elements(xml, klass, register, xml_mapping,
                                  target_prefix: target_prefix)
              end
            end
            if xml_mapping
              generate_attributes(xml, klass, register,
                                  xml_mapping)
            end
          end
        end

        def self.generate_complex_type(xml, klass, type_name, register,
xml_mapping = nil, target_prefix: nil)
          xml.public_send(qn("complexType"), { name: type_name }) do
            if klass.attributes.any?
              xml.public_send(qn("sequence")) do
                generate_elements(xml, klass, register, xml_mapping,
                                  target_prefix: target_prefix)
              end
            end
            generate_attributes(xml, klass, register, xml_mapping)
          end
        end

        def self.generate_elements(xml, klass, register, xml_mapping,
target_prefix: nil)
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
                  # Reference named type by its owning namespace's prefix
                  element_attrs[:type] = qualify_type_ref(
                    nested_type_name,
                    nested_ref_prefix(nested_mapping, target_prefix),
                  )
                  xml.public_send(qn("element"), element_attrs)
                else
                  # Inline anonymous complexType
                  xml.public_send(qn("element"), element_attrs) do
                    xml.public_send(qn("complexType")) do
                      xml.public_send(qn("sequence")) do
                        xml.public_send(qn("element"),
                                        { name: "item", type: get_xsd_type(attr_type) })
                      end
                    end
                  end
                end
              elsif nested_type_name
                # Single nested model - reference by its owning namespace prefix
                xml.public_send(
                  qn("element"),
                  { name: name.to_s,
                    type: qualify_type_ref(
                      nested_type_name,
                      nested_ref_prefix(nested_mapping, target_prefix),
                    ) },
                )
              else
                # Inline anonymous complexType
                xml.public_send(qn("element"), { name: name.to_s }) do
                  generate_complex_type_content(xml, attr_type, register, nil,
                                                target_prefix: target_prefix)
                end
              end
            else
              # Value type
              xsd_type = get_attribute_xsd_type(attr, attr_type, register,
                                                mapping_rule)

              if attr.collection?
                # Collection of simple types
                element_attrs = { name: name.to_s }
                element_attrs[:minOccurs] = "0"
                element_attrs[:maxOccurs] = "unbounded"

                xml.public_send(qn("element"), element_attrs) do
                  xml.public_send(qn("complexType")) do
                    xml.public_send(qn("sequence")) do
                      xml.public_send(qn("element"),
                                      { name: "item", type: xsd_type })
                    end
                  end
                end
              else
                # Simple element
                element_attrs = build_element_attributes(name, xsd_type, attr,
                                                         xml_mapping, name)
                xml.public_send(qn("element"), element_attrs)
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
            attr_attrs[:form] = rule.form.to_s if rule.form

            if rule.documentation
              xml.public_send(qn("attribute"), attr_attrs) do
                xml.public_send(qn("annotation")) do
                  xml.public_send(qn("documentation"), rule.documentation)
                end
              end
            else
              xml.public_send(qn("attribute"), attr_attrs)
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
          end

          # Add form attribute from mapping rule if present
          if xml_mapping
            rule = xml_mapping.find_element(attr_name)
            attrs[:form] = rule.form.to_s if rule&.form
            attrs[:annotation] = rule.documentation if rule&.documentation
          end

          attrs
        end

        def self.has_explicit_xml_mapping?(klass, xml_mapping)
          return true unless xml_mapping.root_element

          base_name = Lutaml::Model::Utils.base_class_name(klass)
          xml_mapping.root_element != base_name
        end

        def self.get_attribute_xsd_type(attr, attr_type, register,
_mapping_rule = nil)
          # 1. Check for deprecated attribute-level xsd_type override
          return attr.options[:xsd_type] if attr.options[:xsd_type]

          # 2. Check if type has xsd_type method (Type-level)
          if attr_type.is_a?(Class) && attr_type < Lutaml::Model::Type::Value
            # Special handling for Reference type
            if attr_type == Lutaml::Model::Type::Reference
              target_xsd_type = get_target_xsd_type(attr, register)
              return attr_type.xsd_type(target_xsd_type)
            end

            return attr_type.xsd_type
          end

          # 3. Fall back to default mapping
          get_xsd_type(attr_type)
        end

        # Collect every distinct XmlNamespace class used anywhere in the model
        # tree: the model's own namespace and nested Serializable models'
        # namespaces (recursively). Type::Value type namespaces are intentionally
        # NOT collected (see the note inside). Deduped by class (the atomic unit).
        # A class-level structural walk — needs no instance.
        def self.collect_namespace_classes(klass, register, seen = Set.new)
          return [] unless klass.is_a?(::Class) && seen.add?(klass)

          classes = []
          own = get_namespace_info(klass)[:class]
          classes << own if own

          klass.attributes.each_value do |attr|
            type_class = attr.type(register)
            next unless type_class

            # Only nested Serializable models contribute namespaces here: their
            # named-type references are prefixed by owning namespace. Type::Value
            # type namespaces are NOT collected — their xsd_type refs are emitted
            # verbatim (unprefixed), so importing their namespace would leave an
            # import the refs never use. (Type::Value namespace support: TODO.)
            if type_class <= Lutaml::Model::Serialize
              classes.concat(
                collect_namespace_classes(type_class, register, seen),
              )
            end
          end

          classes.uniq
        end

        # Get unified namespace information from Model or Type class
        def self.get_namespace_info(klass)
          return {} unless klass.is_a?(::Class)

          # Check for Model class (Serializable)
          if defined?(Lutaml::Model::Serialize) &&
              klass <= Lutaml::Model::Serialize
            return get_model_namespace_info(klass)
          end

          # Check for Type class (Type::Value)
          if defined?(Lutaml::Model::Type::Value) &&
              klass <= Lutaml::Model::Type::Value
            return get_type_namespace_info(klass)
          end

          {}
        end

        class << self
          private

          # Get namespace info from Model class (Serializable)
          def get_model_namespace_info(klass)
            mapping = klass.is_a?(Class) && klass.include?(Lutaml::Model::Serialize) ? klass.mappings_for(:xml) : nil
            return {} unless mapping

            {
              uri: mapping.namespace_uri,
              prefix: mapping.namespace_prefix,
              class: mapping.namespace_class,
            }
          end

          # Get namespace info from Type class (Type::Value)
          def get_type_namespace_info(klass)
            ns = klass.is_a?(Class) && klass <= Lutaml::Model::Type::Value ? klass.namespace_class : nil
            return {} unless ns

            # Handle special symbols
            return { uri: nil, prefix: nil, class: nil } if %i[blank
                                                               inherit].include?(ns)

            # XmlNamespace class
            {
              uri: ns.is_a?(Class) && ns < Lutaml::Xml::Namespace ? ns.uri : nil,
              prefix: ns.is_a?(Class) && ns < Lutaml::Xml::Namespace ? ns.prefix_default : nil,
              class: ns,
            }
          end
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
          }[type] || "xs:string"
        end
      end
    end
  end
end
