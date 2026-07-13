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
          autoload :SimpleTypes,  "#{__dir__}/spec_builder/simple_types"
          autoload :Members,      "#{__dir__}/spec_builder/members"
          autoload :ComplexTypes, "#{__dir__}/spec_builder/complex_types"

          attr_reader :simple_types, :complex_types, :group_types,
                      :elements, :attributes, :attribute_groups,
                      :namespace_classes, :namespace_class_name,
                      :members_builder

          def initialize
            @simple_types = MappingHash.new
            @complex_types = MappingHash.new
            @group_types = MappingHash.new
            @elements = MappingHash.new
            @attributes = MappingHash.new
            @attribute_groups = MappingHash.new
            @namespace_classes = MappingHash.new
            @simple_types_builder  = SimpleTypes.new(self)
            @members_builder       = Members.new(self)
            @complex_types_builder = ComplexTypes.new(self)
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
            uris = []
            uris << requested_uri if requested_uri
            schemas.each do |schema|
              uris << schema.target_namespace if schema.target_namespace
            end
            uris.uniq.each do |uri|
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
            each_schema_item(schemas) { |item, schema| dispatch_lookup(item, schema) }
          end

          def build_complex_types(schemas)
            each_schema_item(schemas) { |item, schema| dispatch_complex(item, schema) }
          end

          def dispatch_lookup(item, schema)
            case item
            when Lutaml::Xml::Schema::Xsd::SimpleType
              @simple_types[item.name] = build_simple_type(item)
            when Lutaml::Xml::Schema::Xsd::Element
              @elements[item.name] = @members_builder.build_top_level_attribute(item, kind: :element)
            when Lutaml::Xml::Schema::Xsd::Attribute
              return if xml_defined_attribute?(schema, item.name)

              @attributes[item.name] = @members_builder.build_top_level_attribute(item, kind: :attribute)
            when Lutaml::Xml::Schema::Xsd::AttributeGroup
              @attribute_groups[item.name] = @complex_types_builder.build_attribute_group(item)
            end
          end

          def dispatch_complex(item, _schema)
            case item
            when Lutaml::Xml::Schema::Xsd::ComplexType
              @complex_types[item.name] = @complex_types_builder.build(item)
            when Lutaml::Xml::Schema::Xsd::Group
              @group_types[item.name] = @complex_types_builder.build_group(item)
            end
          end

          # Add the built-in XSD types (NonNegativeInteger, NormalizedString,
          # etc.) as Definitions::RestrictedType entries.
          def add_supported_types
            SupportedDataTypes.each do |name, info|
              next if info[:skippable]

              str_name = name.to_s
              @simple_types[str_name] = @simple_types_builder.build_supported(str_name, info)
            end
          end

          # Every generated class spec keyed by name. Used by the orchestrator
          # to build CompiledOutput entries without reaching into the builder's
          # internal hashes.
          def all_models
            @simple_types.merge(@complex_types).merge(@group_types)
          end

          # Stamp `required_files` on every walked complex / group model.
          # The skippable predicate is supplied by SupportedDataTypes —
          # the orchestrator never has to thread the type table through.
          def finalize_required_files!
            (@complex_types.each_value.to_a + @group_types.each_value.to_a).each do |model|
              model.required_files = Renderers::RequiredFilesCalculator
                .for_xml(model, skippable_type: SupportedDataTypes.method(:skippable?))
            end
          end

          # Public surface used by the Members sub-builder to register
          # nested anonymous types it encounters during attribute /
          # element resolution.
          def build_simple_type(simple_type) = @simple_types_builder.build(simple_type)
          def build_complex_type(complex_type) = @complex_types_builder.build(complex_type)

          private

          # Recursively walks `schemas` (following include / import) and
          # yields each resolved element-order item with its owning schema.
          def each_schema_item(schemas, &dispatch)
            schemas.each do |schema|
              each_schema_item(schema.include, &dispatch) if schema.include&.any?
              each_schema_item(schema.import, &dispatch)  if schema.import&.any?
              schema.resolved_element_order.each { |item| yield(item, schema) }
            end
          end

          def xml_defined_attribute?(schema, name)
            schema.target_namespace == XmlCompiler::XML_NAMESPACE_URI &&
              XmlCompiler::XML_DEFINED_ATTRIBUTES.key?(name)
          end
        end
      end
    end
  end
end
