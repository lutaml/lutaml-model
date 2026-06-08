# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # Walks parsed XSD AST objects and emits Definitions::* specs.
        # Holds the in-progress class hashes that ref resolution looks
        # up by name. Stateful by design (refs and forward references
        # demand it); kept out of XmlCompiler.rb so the orchestrator
        # stays focused on parse/dispatch.
        class SpecBuilder
          # XSD built-in type table. Keys are the XSD type names; values
          # describe how to render the generated subclass.
          # `skippable: true` means the XSD type maps directly to a
          # Lutaml primitive symbol and needs no generated class.
          TC = Lutaml::Model::Type::TYPE_CODES

          SUPPORTED_DATA_TYPES = {
            nonNegativeInteger: { skippable: false, class_name: TC[:string],
                                  validations: { pattern: /\+?[0-9]+/ } },
            normalizedString: { skippable: false, class_name: TC[:string],
                                validations: { transform: "value.gsub(/[\\r\\n\\t]/, ' ')" } },
            positiveInteger: { skippable: false, class_name: TC[:integer],
                               validations: { min_inclusive: 0 } },
            unsignedShort: { skippable: false, class_name: TC[:integer],
                             validations: { min_inclusive: 0, max_inclusive: 65535 } },
            base64Binary: { skippable: false, class_name: TC[:string],
                            validations: { pattern: /\A([A-Za-z0-9+\/]+={0,2}|\s)*\z/ } },
            unsignedLong: { skippable: false, class_name: TC[:integer],
                            validations: { min_inclusive: 0, max_inclusive: 18446744073709551615 } },
            unsignedByte: { skippable: false, class_name: TC[:integer],
                            validations: { min_inclusive: 0, max_inclusive: 255 } },
            unsignedInt: { skippable: false, class_name: TC[:integer],
                           validations: { min_inclusive: 0, max_inclusive: 4294967295 } },
            hexBinary: { skippable: false, class_name: TC[:string],
                         validations: { pattern: /([0-9a-fA-F]{2})*/ } },
            language: { skippable: false, class_name: TC[:string],
                        validations: { pattern: /\A[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*\z/ } },
            dateTime: { skippable: true, class_name: TC[:date_time] },
            boolean: { skippable: true, class_name: TC[:boolean] },
            integer: { skippable: true, class_name: TC[:integer] },
            decimal: { skippable: true, class_name: TC[:decimal] },
            string: { skippable: true, class_name: TC[:string] },
            double: { skippable: true, class_name: TC[:float] },
            NCName: { skippable: false, class_name: TC[:string],
                      validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
            anyURI: { skippable: false, class_name: TC[:string],
                      validations: { pattern: "\\A\#{URI::DEFAULT_PARSER.make_regexp(%w[http https ftp])}\\z" } },
            token: { skippable: false, class_name: TC[:string],
                     validations: { pattern: /\A[^\t\n\f\r ]+(?: [^\t\n\f\r ]+)*\z/ } },
            byte: { skippable: false, class_name: TC[:integer],
                    validations: { min_inclusive: -128, max_inclusive: 127 } },
            long: { skippable: false, class_name: TC[:decimal] },
            int: { skippable: true, class_name: TC[:integer] },
            id: { skippable: false, class_name: TC[:string],
                  validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
          }.freeze

          autoload :SimpleTypes, "#{__dir__}/spec_builder/simple_types"
          autoload :Members,     "#{__dir__}/spec_builder/members"

          attr_reader :simple_types, :complex_types, :group_types,
                      :elements, :attributes, :attribute_groups,
                      :namespace_classes

          def initialize
            @simple_types = MappingHash.new
            @complex_types = MappingHash.new
            @group_types = MappingHash.new
            @elements = MappingHash.new
            @attributes = MappingHash.new
            @attribute_groups = MappingHash.new
            @namespace_classes = MappingHash.new
            @simple_types_builder = SimpleTypes.new(self)
            @members_builder = Members.new(self)
          end

          def populate_default_attributes
            XmlCompiler::XML_DEFINED_ATTRIBUTES.each do |name, w3c_class|
              @attributes[name] = Definitions::Attribute.new(
                name: Utils.snake_case(name),
                type: Definitions::TypeRef.new(kind: :w3c, value: w3c_class),
                xml_name: name,
                kind: :attribute,
              )
            end
          end

          def collect_namespaces(schemas, options)
            requested_uri = options[:namespace]
            uris = Set.new
            uris.add(requested_uri) if requested_uri
            schemas.each do |schema|
              uris.add(schema.target_namespace) if schema.target_namespace
            end
            uris.each do |uri|
              next if uri.nil? || uri.empty?

              prefix = options[:prefix] if requested_uri == uri
              ns = Definitions::Namespace.new(
                class_name: NamespaceNaming.class_name_for(uri),
                uri: uri,
                prefix_default: prefix || NamespaceNaming.prefix_for(uri),
              )
              @namespace_classes[ns.class_name] = ns
            end
            # Resolve the namespace_class_name once. When the caller
            # passed :namespace, every generated complex type gets this
            # name. Mirrors XmlCompiler::ComplexType#setup_options on main.
            @namespace_class_name =
              requested_uri && @namespace_classes.values.find { |ns| ns.uri == requested_uri }&.class_name
          end

          def walk_schemas(schemas)
            return if schemas.empty?

            # Two-pass walk: register top-level Elements / Attributes /
            # AttributeGroups / SimpleTypes first so forward references
            # from ComplexTypes / Groups resolve in pass 2.
            collect_lookups(schemas)
            build_complex_types(schemas)
          end

          def collect_lookups(schemas)
            schemas.each do |schema|
              collect_lookups(schema.include) if schema.include&.any?
              collect_lookups(schema.import)  if schema.import&.any?
              schema.resolved_element_order.each do |item|
                dispatch_lookup(item, schema)
              end
            end
          end

          def build_complex_types(schemas)
            schemas.each do |schema|
              build_complex_types(schema.include) if schema.include&.any?
              build_complex_types(schema.import)  if schema.import&.any?
              schema.resolved_element_order.each do |item|
                dispatch_complex(item, schema)
              end
            end
          end

          def dispatch_lookup(item, schema)
            case item
            when Lutaml::Xml::Schema::Xsd::SimpleType
              @simple_types[item.name] = build_simple_type(item)
            when Lutaml::Xml::Schema::Xsd::Element
              @elements[item.name] = build_top_level_attribute(item, kind: :element)
            when Lutaml::Xml::Schema::Xsd::Attribute
              return if xml_defined_attribute?(schema, item.name)

              @attributes[item.name] = build_top_level_attribute(item, kind: :attribute)
            when Lutaml::Xml::Schema::Xsd::AttributeGroup
              @attribute_groups[item.name] = build_attribute_group_members(item)
            end
          end

          def dispatch_complex(item, _schema)
            case item
            when Lutaml::Xml::Schema::Xsd::ComplexType
              @complex_types[item.name] = build_complex_type(item)
            when Lutaml::Xml::Schema::Xsd::Group
              @group_types[item.name] = build_group_model(item)
            end
          end

          # Add the built-in XSD types (NonNegativeInteger, NormalizedString,
          # etc.) as Definitions::RestrictedType entries.
          def add_supported_types
            SUPPORTED_DATA_TYPES.each do |name, info|
              next if info[:skippable]

              str_name = name.to_s
              @simple_types[str_name] = build_supported_type(str_name, info)
            end
          end

          # Every generated class spec keyed by name. Used by the orchestrator
          # to build CompiledOutput entries without reaching into the builder's
          # internal hashes.
          def all_models
            @simple_types.merge(@complex_types).merge(@group_types)
          end

          # Stamp `required_files` on every walked complex / group model.
          # Owned by the builder so the orchestrator doesn't have to thread
          # SUPPORTED_DATA_TYPES through a callable predicate.
          def finalize_required_files!
            (@complex_types.each_value.to_a + @group_types.each_value.to_a).each do |model|
              model.required_files = Renderers::RequiredFilesCalculator
                .for_xml(model, skippable_type: method(:skippable_type?))
            end
          end

          # Simple-type building delegated to SimpleTypes sub-builder.
          def build_simple_type(simple_type) = @simple_types_builder.build(simple_type)
          def build_supported_type(name, info) = @simple_types_builder.build_supported(name, info)

          def skippable_type?(value)
            SUPPORTED_DATA_TYPES.dig(value.to_sym, :skippable) || false
          end

          private

          def xml_defined_attribute?(schema, name)
            schema.target_namespace == XmlCompiler::XML_NAMESPACE_URI &&
              XmlCompiler::XML_DEFINED_ATTRIBUTES.key?(name)
          end

          # ----------------------------------------------------------------
          # Complex types
          # ----------------------------------------------------------------

          def build_complex_type(complex_type)
            model = Definitions::Model.new(
              class_name: Utils.camel_case(complex_type.name),
              xml_root: Definitions::XmlRoot.new(kind: :element, name: complex_type.name),
              mixed: !!complex_type.mixed,
              namespace_class_name: @namespace_class_name,
            )

            resolved_element_order(complex_type).each do |element|
              add_complex_child(model, element)
            end
            model
          end

          def add_complex_child(model, element)
            case element
            when Lutaml::Xml::Schema::Xsd::Attribute
              attr = build_attribute_def(element)
              model.members << attr if attr
            when Lutaml::Xml::Schema::Xsd::Sequence
              model.members << build_sequence(element)
            when Lutaml::Xml::Schema::Xsd::Choice
              model.members << build_choice(element)
            when Lutaml::Xml::Schema::Xsd::ComplexContent
              apply_complex_content(element, model)
            when Lutaml::Xml::Schema::Xsd::AttributeGroup
              model.members.concat(build_attribute_group_members(element))
            when Lutaml::Xml::Schema::Xsd::Group
              add_group_to_model(element, model)
            when Lutaml::Xml::Schema::Xsd::SimpleContent
              model.simple_content = build_simple_content(element)
            end
          end

          def apply_complex_content(content, model)
            model.mixed = true if content.mixed

            if (ext = content.extension)
              model.parent_class = qualified_class(ext.base)
              resolved_element_order(ext).each { |c| add_complex_child(model, c) }
            elsif (res = content.restriction)
              model.parent_class = qualified_class(res.base)
              resolved_element_order(res).each do |c|
                # XSD: restrictions on complex content inherit sequence/choice/group from base.
                next if c.is_a?(Lutaml::Xml::Schema::Xsd::Sequence) ||
                  c.is_a?(Lutaml::Xml::Schema::Xsd::Choice) ||
                  c.is_a?(Lutaml::Xml::Schema::Xsd::Group)

                add_complex_child(model, c)
              end
            end
          end

          def qualified_class(raw)
            return "Lutaml::Model::Serializable" if raw.nil?

            Utils.camel_case(Utils.last_of_split(raw))
          end

          def add_group_to_model(group, model)
            # Anonymous group OR named-but-not-referenced group: unwrap
            # the inner sequence/choice inline into the model. (Matches
            # the old XmlCompiler::Group rendering, which only emitted
            # import_model_attributes/mappings when `ref` was set.)
            if group.ref.nil?
              add_anonymous_group_contents(group, model)
              @group_types[group.name] = build_group_model(group) if group.name && !@group_types.key?(group.name)
              return
            end

            model.members << Definitions::GroupImport.new(
              name: Utils.snake_case(Utils.last_of_split(group.ref)),
            )
          end

          def add_anonymous_group_contents(group, model)
            inner = group.sequence || group.choice
            return unless inner

            built = case inner
                    when Lutaml::Xml::Schema::Xsd::Sequence then build_sequence(inner)
                    when Lutaml::Xml::Schema::Xsd::Choice   then build_choice(inner)
                    end
            model.members << built if built
          end

          # Member building delegated to Members sub-builder.
          def build_attribute_def(attr) = @members_builder.build_attribute(attr)
          def build_element_def(element) = @members_builder.build_element(element)
          def build_top_level_attribute(item, kind:) = @members_builder.build_top_level_attribute(item, kind: kind)
          def build_sequence(sequence) = @members_builder.build_sequence(sequence)
          def build_choice(choice) = @members_builder.build_choice(choice)

          # ----------------------------------------------------------------
          # Groups (importable type-only models)
          # ----------------------------------------------------------------

          def build_group_model(group)
            inner_members = []
            inner = group.sequence || group.choice
            if inner
              built = case inner
                      when Lutaml::Xml::Schema::Xsd::Sequence then build_sequence(inner)
                      when Lutaml::Xml::Schema::Xsd::Choice   then build_choice(inner)
                      end
              inner_members << built if built
            end

            base_name = group.name || Utils.last_of_split(group.ref)
            # Groups render unwrapped (module_wrappable: false) so they
            # cannot reference the namespace constant by bare name.
            # Importers inherit the namespace from the wrapping class.
            Definitions::Model.new(
              class_name: Utils.camel_case(base_name),
              xml_root: Definitions::XmlRoot.new(kind: :type_name, name: base_name),
              members: inner_members,
              module_wrappable: false,
              lazy_register: true,
            )
          end

          # ----------------------------------------------------------------
          # Attribute groups (flattened into model.members)
          # ----------------------------------------------------------------

          def build_attribute_group_members(attribute_group)
            ref = attribute_group.ref
            if ref && !attribute_group.name
              target = @attribute_groups[Utils.last_of_split(ref)]
              return Array(target)
            end

            members = []
            resolved_element_order(attribute_group).each do |item|
              case item
              when Lutaml::Xml::Schema::Xsd::Attribute
                attr_spec = build_attribute_def(item)
                members << attr_spec if attr_spec
              when Lutaml::Xml::Schema::Xsd::AttributeGroup
                members.concat(build_attribute_group_members(item))
              end
            end
            members
          end

          # ----------------------------------------------------------------
          # Simple content (XSD-only)
          # ----------------------------------------------------------------

          def build_simple_content(simple_content)
            additional = []
            base_class = nil
            if simple_content.extension
              ext = simple_content.extension
              base_class = ext.base
              resolved_element_order(ext).each do |item|
                case item
                when Lutaml::Xml::Schema::Xsd::Attribute
                  attr = build_attribute_def(item)
                  additional << attr if attr
                when Lutaml::Xml::Schema::Xsd::AttributeGroup
                  additional.concat(build_attribute_group_members(item))
                end
              end
            elsif simple_content.restriction
              base_class = simple_content.restriction.base
            end

            Definitions::SimpleContent.new(
              base_class: base_class,
              additional_attributes: additional,
            )
          end

          public

          # ----------------------------------------------------------------
          # Element ordering helper (mirrors original behavior).
          # Public so sub-builders (Members, ComplexTypes) can call it
          # without breaking encapsulation via send().
          # ----------------------------------------------------------------

          def resolved_element_order(object)
            return [] if object.element_order.nil?

            if object.is_a?(Lutaml::Xml::Schema::Xsd::Base)
              return object.resolved_element_order
            end

            object.element_order.each_with_object(object.element_order.dup) do |builder, array|
              next array.delete(builder) if builder.text? || XmlCompiler::ELEMENT_ORDER_IGNORABLE.include?(builder.name)

              index = 0
              array.each_with_index do |element, i|
                next unless element == builder

                array[i] = Array(object.public_send(Utils.snake_case(builder.name)))[index]
                index += 1
              end
            end
            object.element_order
          end
        end
      end
    end
  end
end
