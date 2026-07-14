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
        def self.validate_xsd_types!(klass, register)
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
                validate_xsd_types!(attr_type, register)
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
                import_attrs[:schemaLocation] =
                  ns_class.schema_location
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
                           end

            type_name = xml_mapping.type_name_value

            # Generate XSD based on three patterns:
            # Pattern 1: element only -> inline anonymous complexType
            # Pattern 2: type_name only -> named complexType (no element)
            # Pattern 3: both element and type_name -> element + named complexType

            if element_name && type_name
              # Pattern 3: Both element and named type
              xml.element(name: element_name, type: type_name)
              generate_complex_type(xml, klass, type_name, register,
                                    xml_mapping)
            elsif type_name && !element_name
              # Pattern 2: Type-only (no element)
              generate_complex_type(xml, klass, type_name, register,
                                    xml_mapping)
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
              generate_complex_type(xml, attr_type, nested_type_name, register,
                                    nested_mapping)
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
              elsif nested_type_name
                # Single nested model - Reference named type
                xml.element(name: name.to_s, type: nested_type_name)
              else
                # Inline anonymous complexType
                xml.element(name: name.to_s) do
                  generate_complex_type_content(xml, attr_type, register, nil)
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

                xml.element(element_attrs) do
                  xml.complexType do
                    xml.sequence do
                      emit_value_element(xml, { name: "item" }, xsd_type,
                                         attr_type, attr)
                    end
                  end
                end
              else
                # Simple element
                element_attrs = build_element_attributes(name, xsd_type, attr,
                                                         xml_mapping, name)
                emit_value_element(xml, element_attrs, xsd_type, attr_type, attr)
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
            emit_xsd_attribute(xml, attr, rule, xsd_type, attr_type)
          end
        end

        # Emit an `xs:attribute`, inlining an `xs:restriction` when the attribute
        # is a constrained value type (its `type=` moves into the restriction
        # base) and/or an annotation when the mapping carries documentation.
        def self.emit_xsd_attribute(xml, attr, rule, xsd_type, attr_type)
          facets = effective_facets(attr, attr_type)
          restricted = facets.any?

          attr_attrs = { name: rule.name }
          attr_attrs[:type] = xsd_type unless restricted
          attr_attrs[:use] = "required" if attr.options[:required]
          attr_attrs[:form] = rule.form.to_s if rule.form

          return xml.attribute(attr_attrs) unless restricted || rule.documentation

          xml.attribute(attr_attrs) do
            if rule.documentation
              xml.annotation { xml.documentation(rule.documentation) }
            end
            emit_restriction(xml, xsd_type, facets, attr_type) if restricted
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

        # Emit an `xs:element` for a value type, inlining an `xs:restriction`
        # (its `type=` moving into the restriction base) when the type is a
        # constrained value type, else a flat `type=` reference. `merge` keeps an
        # existing `type` key in position; `except` drops it for the inline case.
        def self.emit_value_element(xml, attrs, xsd_type, attr_type, attr)
          facets = effective_facets(attr, attr_type)
          if facets.any?
            xml.element(attrs.except(:type)) do
              emit_restriction(xml, xsd_type, facets, attr_type)
            end
          else
            xml.element(attrs.merge(type: xsd_type))
          end
        end

        # Effective xs:restriction facet set for an attribute: the conjunctive
        # merge of its Layer-1 options and the Layer-2 facets on its value type
        # (reusing the runtime resolver so the schema matches what is enforced).
        def self.effective_facets(attr, attr_type)
          return {} unless attr_type.is_a?(Class) &&
            attr_type < Lutaml::Model::Type::Value

          attr.effective_restriction_facets(attr_type)
        end

        def self.emit_restriction(xml, base, facets, type)
          xml.simpleType do
            xml.restriction(base: base) do
              emit_restriction_facets(xml, facets, type)
            end
          end
        end

        # Emit the facet child elements in canonical W3C xs:restriction order.
        # Bounds/enumeration carry base-typed values (serialized to their lexical
        # form); lengths/digits/whiteSpace are plain scalars. Accumulated patterns
        # are conjunctive (a value must match all), which one xs:restriction
        # cannot express — sibling xs:pattern facets are alternatives (OR) — so a
        # multi-pattern type fails fast rather than export a weaker OR schema.
        def self.emit_restriction_facets(xml, facets, type)
          emit_bound(xml, :minExclusive, facets[:min_exclusive], type)
          emit_bound(xml, :minInclusive, facets[:min_inclusive], type)
          emit_bound(xml, :maxExclusive, facets[:max_exclusive], type)
          emit_bound(xml, :maxInclusive, facets[:max_inclusive], type)
          emit_facet(xml, :totalDigits, facets[:total_digits])
          emit_facet(xml, :fractionDigits, facets[:fraction_digits])
          emit_facet(xml, :length, facets[:length])
          emit_facet(xml, :minLength, facets[:min_length])
          emit_facet(xml, :maxLength, facets[:max_length])
          Array(facets[:enumeration]).each do |value|
            emit_facet(xml, :enumeration, lexical_value(type, value))
          end
          emit_facet(xml, :whiteSpace, facets[:white_space])
          patterns = Array(facets[:pattern])
          if patterns.size > 1
            raise Lutaml::Model::Error,
                  "Cannot export #{patterns.size} conjunctive patterns on " \
                  "#{type} to a single xs:restriction: sibling xs:pattern " \
                  "facets are alternatives (OR), and XSD cannot express " \
                  "conjunction (AND) without nested restriction derivation, " \
                  "which is not yet supported."
          end
          patterns.each { |re| emit_facet(xml, :pattern, pattern_value(re)) }
        end

        # Ruby regexp flags whose semantics XSD's regular-expression subset
        # cannot carry (case-insensitive, dot-matches-newline, extended). These
        # are not visible in the pattern source, so the XSD validator below
        # cannot catch them.
        UNSUPPORTED_XSD_REGEX_FLAGS =
          Regexp::IGNORECASE | Regexp::MULTILINE | Regexp::EXTENDED

        # Translate a Ruby Regexp into an XSD pattern string. XSD patterns are
        # implicitly whole-string anchored, so strip Ruby's whole-string/line
        # anchors, then let the XSD regexp validator reject any remaining
        # construct XSD cannot express (rather than emit invalid XSD).
        def self.pattern_value(regexp)
          reject_unsupported_regex_flags!(regexp)
          source = strip_ruby_anchors(regexp.source)
          reject_invalid_xsd_pattern!(regexp, source)
          source
        end

        def self.reject_unsupported_regex_flags!(regexp)
          return if regexp.options.nobits?(UNSUPPORTED_XSD_REGEX_FLAGS)

          raise Lutaml::Model::Error,
                "Cannot export pattern #{regexp.inspect} to xs:pattern: " \
                "the i/m/x flags are not expressible in XSD's regexp subset."
        end

        # Remove a leading `\A`/`^` and a trailing `\z`/`\Z`/`$`, treating each
        # only as an anchor. Whether a `\`-prefixed token is an anchor or an
        # escaped literal depends on backslash-run parity: an ODD run ends in a
        # lone backslash that binds the following char as the anchor (`\z`),
        # while an EVEN run is all escaped-backslash pairs, leaving a literal
        # (`\\z` == backslash + "z"). Likewise `$` is an anchor only when an
        # EVEN number of backslashes precede it (`\$` == literal dollar).
        def self.strip_ruby_anchors(source)
          source = strip_leading_anchor(source)
          strip_trailing_anchor(source)
        end

        def self.strip_leading_anchor(source)
          return source[1..] if source.start_with?("^")

          run = source[/\A\\+/].to_s.length
          return source unless run.odd? && source[run] == "A"

          # Keep the escaped-pair backslashes; drop the anchor's `\A`.
          source[0, run - 1] + source[(run + 1)..]
        end

        def self.strip_trailing_anchor(source)
          if (m = source[/\\+[zZ]\z/]) && (m.length - 1).odd?
            return source[0...-2]
          end
          if source.end_with?("$") && source[0...-1][/\\*\z/].length.even?
            return source[0...-1]
          end

          source
        end

        # Validate the pattern against XSD's regexp grammar using Nokogiri as the
        # XSD reference validator. This is exact — no false positives/negatives
        # from a hand-maintained construct list — so any lazy quantifier,
        # lookaround, or char-class intersection XSD cannot express is rejected
        # with the validator's own diagnostic. The Oga adapter does not load
        # Nokogiri, so when it is absent the anchor-stripped source is emitted
        # best-effort without this deep validation.
        def self.reject_invalid_xsd_pattern!(regexp, source)
          return unless defined?(::Nokogiri::XML::Schema)

          probe = <<~XSD
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:simpleType name="p">
                <xs:restriction base="xs:string">
                  <xs:pattern value="#{xsd_escape(source)}"/>
                </xs:restriction>
              </xs:simpleType>
            </xs:schema>
          XSD
          schema = ::Nokogiri::XML::Schema(probe)
          return if schema.errors.empty?

          raise_inexpressible_pattern!(regexp, schema.errors.first.message)
        rescue ::Nokogiri::XML::SyntaxError => e
          raise_inexpressible_pattern!(regexp, e.message)
        end

        def self.raise_inexpressible_pattern!(regexp, detail)
          raise Lutaml::Model::Error,
                "Cannot export pattern #{regexp.inspect} to xs:pattern: " \
                "it is not expressible in XSD's regexp subset (#{detail})."
        end

        def self.xsd_escape(text)
          text.gsub("&", "&amp;").gsub("<", "&lt;").gsub('"', "&quot;")
        end

        def self.emit_bound(xml, element, value, type)
          emit_facet(xml, element, lexical_value(type, value)) unless value.nil?
        end

        # Serialize a base-typed facet value to its XSD lexical form, tolerating
        # both already-cast values and raw literals from the facet DSL (e.g. a
        # temporal bound declared as an ISO string). `cast` is idempotent for an
        # already-cast value.
        def self.lexical_value(type, value)
          type.serialize(type.cast(value))
        end

        def self.emit_facet(xml, element, value)
          return if value.nil?

          xml.public_send(element, value: value.to_s)
        end

        def self.has_explicit_xml_mapping?(klass, xml_mapping)
          return true unless xml_mapping.root_element

          base_name = Lutaml::Model::Utils.base_class_name(klass)
          xml_mapping.root_element != base_name
        end

        def self.get_attribute_xsd_type(attr, attr_type, register,
_mapping_rule = nil)
          if attr.union?
            raise Lutaml::Model::UnionSchemaUnsupportedError.new(attr.name, "XSD")
          end

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

        def self.collect_type_namespaces(klass, register)
          namespaces = Set.new

          klass.attributes.each_value do |attr|
            type_class = attr.type(register)
            next unless type_class

            # Use unified get_namespace_info method
            ns_info = get_namespace_info(type_class)
            namespaces << ns_info[:class] if ns_info[:class]
          end

          namespaces.to_a
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
