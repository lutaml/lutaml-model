# frozen_string_literal: true

module Lutaml
  module Lml
    # Builds domain model objects from processed parse hashes, applying
    # source positions as non-serialized metadata.
    class DocumentBuilder
      # Default registry: builder keys → LML model classes.
      # Callers needing a different mapping can pass their own registry
      # to `new`; this constant documents the default composition.
      DEFAULT_REGISTRY = {
        document: ::Lutaml::Lml::Document,
        package: ::Lutaml::Lml::Package,
        class: ::Lutaml::Lml::UmlClass,
        enum: ::Lutaml::Lml::Enum,
        data_type: ::Lutaml::Lml::DataType,
        diagram: ::Lutaml::Lml::Diagram,
        attribute: ::Lutaml::Lml::TopElementAttribute,
        cardinality: ::Lutaml::Lml::Cardinality,
        association: ::Lutaml::Lml::Association,
        operation: ::Lutaml::Lml::Operation,
        constraint: ::Lutaml::Lml::Constraint,
        value: ::Lutaml::Lml::Value,
        instance: ::Lutaml::Lml::Instance,
        instance_collection: ::Lutaml::Lml::InstanceCollection,
        view_import: ::Lutaml::Lml::ViewImport,
        view_filter: ::Lutaml::Lml::ViewFilter,
        mapping: ::Lutaml::Lml::Mapping,
        string_format: ::Lutaml::Lml::StringFormat,
        derived_field: ::Lutaml::Lml::DerivedField,
        member_field: ::Lutaml::Lml::MemberField,
        namespace: ::Lutaml::Lml::Namespace,
        serialization_mapping: ::Lutaml::Lml::SerializationMapping,
      }.freeze

      attr_reader :registry

      def initialize(registry = DEFAULT_REGISTRY)
        @registry = registry
      end

      FACTORY_KEYS = %i[
        document package class enum data_type diagram view_import view_filter
        attribute association operation constraint value cardinality mapping
        string_format derived_field namespace serialization_mapping
        instance instance_collection
      ].freeze

      MEMBER_KEY_MAP = {
        packages: :package,
        classes: :class,
        enums: :enum,
        data_types: :data_type,
        diagrams: :diagram,
        view_imports: :view_import,
        attributes: :attribute,
        associations: :association,
        operations: :operation,
        constraints: :constraint,
        values: :value,
        mappings: :mapping,
        member_fields: :member_field,
        namespaces: :namespace,
        serialization_mappings: :serialization_mapping,
        instances: :instance,
      }.freeze

      FACTORY_KEYS.each do |key|
        define_method(:"build_#{key}") { |hash| build(key, hash) }
      end

      def build(key, hash)
        @registry.fetch(key).new.tap { |model| set_model(model, hash) }
      end

      private

      def set_model(model, hash)
        hash = build_members(model, hash)
        apply_collection_members(model, hash)
        set_model_attributes(model, hash)
        expand_class_specializer(model, hash)
      end

      # The prefix specializer (`abstract class Foo`) expands to the
      # canonical `abstract true` declaration (RS 3001 par. Declaration
      # modifiers); the class-level modifier capture is not a block member.
      def expand_class_specializer(model, hash)
        return unless hash[:modifier].to_s == 'abstract' && model.class.attributes.key?(:is_abstract)

        model.is_abstract = true
      end

      def set_model_attributes(model, hash)
        hash.each do |key, value|
          if key == :position
            attach_position(model, value)
            next
          end

          apply_attribute(model, key, value)
        end
      end

      def attach_position(model, value)
        return unless model.is_a?(Positioned) && value.is_a?(Hash)

        model.source_position = SourcePosition.new(**value)
      end

      def build_members(model, hash)
        members = hash.delete(:members)
        members.to_a.each do |member_hash|
          record_model_version(model, member_hash)
          add_members(model, member_hash)
          set_model_attributes(model, member_hash)
        end
        hash
      end

      # A `models <Name> version "x.y.z"` header travels with the block's
      # member hash; the block itself flattens into the document, so the
      # version is recorded on the document before the name is dropped.
      def record_model_version(model, hash)
        return unless model.class.attributes.key?(:model_versions)
        return unless hash.key?(:version)

        name = hash[:name].to_s
        model.model_versions[name] = unquote(hash.delete(:version)).to_s
      end

      def apply_attribute(model, key, value)
        return unless model.class.attributes.key?(key.to_sym)

        if model.class.attributes[key.to_sym].options[:collection]
          append_collection(model, key, value)
        else
          model.public_send("#{key}=", value)
        end
      end

      def append_collection(model, key, value)
        values = model.public_send(key).to_a
        value.is_a?(Array) ? values.concat(value) : values << value
        model.public_send("#{key}=", values)
      end

      def add_members(model, hash)
        expand_declared_members(model, hash)
        normalize_namespace_declaration(hash)
        normalize_serialization_mapping(hash)
        expand_instances_collection_name(hash)
        expand_nested_members(model, hash)
        apply_collection_members(model, hash)

        remap_filter_keys(hash, model)
      end

      # Builds collection-shaped keys through the registry rather than
      # letting lutaml-model cast raw hashes, so nested entities keep
      # their non-serialized source metadata (positions).
      def apply_collection_members(model, hash)
        model.instances = build(:instance_collection, hash.delete(:instances)) if model.is_a?(Document) && hash.key?(:instances)

        MEMBER_KEY_MAP.each do |plural_key, singular_key|
          data = hash.delete(plural_key)
          next if data.nil?

          entries = data.is_a?(Array) ? data : [data]
          entries.each do |entry|
            ensure_collection(model, plural_key) << build(singular_key, entry)
          end
        end
      end

      # RS 3001 §Enums: an enum-level `values { v1, v2 }` shorthand
      # expands into plain members.
      def expand_value_set_declaration(model, hash)
        decl = hash.delete(:value_set_decl) or return
        Array(decl[:items]).each do |item|
          name = unquote(item[:item])
          model.attributes << TopElementAttribute.new(name: name)
        end
      end

      # RS 3001 §Value: the canonical `value` construct normalizes into
      # the same member shape the bare-identifier shortcut produces.
      def expand_value_declaration(model, hash)
        decl = hash.delete(:value_decl) or return
        inner = decl.fetch(:attributes)

        # Route the value block's members onto the entry: descriptions
        # and payload pairs ride the nested attributes, instance bodies
        # become the entry's instances (RS 3001 §Enums values carrying
        # instances).
        entry = { name: inner[:name] }
        entry[:position] = inner[:position] if inner[:position]
        entry[:attributes] = inner[:attributes] if inner[:attributes]
        if inner[:properties]
          entry[:properties] = Array(inner[:properties]).flat_map do |pair|
            pair.is_a?(Hash) ? [pair] : Array(pair)
          end
        end
        entry[:instances] = inner[:instances] if inner[:instances]
        append_collection(model, :attributes, build(:attribute, entry))
      end

      # Namespace declaration bodies arrive as keyword-line members
      # ({uri: …}, {prefix: …}); flatten them onto the namespace hash.
      def normalize_namespace_declaration(hash)
        ns = hash[:namespaces] or return
        Array(ns.delete(:members)).each do |pair|
          pair.each { |key, value| ns[key] = unquote(value) }
        end
      end

      # Serialization mapping rules arrive keyed by their line construct
      # ({map_element: {wire:, field:}}); normalize into plain MappingRule
      # hashes so the model cast lands typed rules.
      def normalize_serialization_mapping(hash)
        mapping = hash[:serialization_mappings] or return
        rules = Array(mapping[:rules])
        return if rules.any? && rules.all? { |e| e.is_a?(Hash) && e.key?(:kind) }

        rules = rules.filter_map do |entry|
          next nil unless entry.is_a?(Hash)

          next { kind: 'map', wire: unquote(entry[:wire]), field: unquote(entry[:to]) } if entry[:wire] && entry[:to]

          first_key = entry.keys.first
          kind = first_key.to_s
          body = entry[first_key] || {}
          unless body.is_a?(Hash)
            kind_n = normalize_mapping_kind(kind)
            next nil if body.to_s.empty?

            term = unquote(body)
            next { kind: kind_n, wire: term, field: term } if %w[element attribute map].include?(kind_n)

            if kind_n == 'namespace'
              mapping[:namespace_ref] = term
              next nil
            end

            next { kind: kind_n, field: term }
          end
          if kind == 'element_name'
            mapping[:element_name] = unquote(body[:element_name])
            next nil
          end
          if kind == 'map_namespace'
            mapping[:namespace_ref] = unquote(body[:namespace_ref])
            next nil
          end
          normalized = { kind: normalize_mapping_kind(kind) }
          wire = body[:wire] || body[:element_wire]
          normalized[:wire] = unquote(wire) if wire
          field = body[:field] || body[:to_field] || body[:element_field] ||
                  body[:attribute_field] || body[:to]
          normalized[:field] = unquote(field) if field
          normalized[:mode] = body[:mode] if body[:mode]
          normalized[:namespace_ref] = unquote(body[:namespace_ref]) if body[:namespace_ref]
          normalized
        end
        mapping[:rules] = rules
      end

      def normalize_mapping_kind(kind)
        {
          'map_element' => 'element', 'map_attribute' => 'attribute',
          'map_content' => 'content', 'map_namespace' => 'namespace',
          'map_key' => 'key', 'map_value' => 'value', 'map' => 'map',
          'legacy_map' => 'map'
        }.fetch(kind, kind)
      end

      # A named instances collection (`instances "Glazes" { ... }`) arrives
      # with its name as a sibling of the collection body; move it inside
      # so the InstanceCollection carries it.
      def expand_instances_collection_name(hash)
        return unless hash.key?(:instances) && hash.key?(:name)

        name = unquote(hash.delete(:name))
        body = hash[:instances].is_a?(Hash) ? hash[:instances] : {}
        body[:name] = name unless body.key?(:name)
      end

      # The document root is a repetition of top-level constructs (RS 3001:
      # documents interleave declarations), so models/packages blocks nest
      # their members one level down; recurse into them.
      def expand_nested_members(model, hash)
        return unless hash.key?(:members)

        members = hash.delete(:members)
        members.to_a.each do |nested|
          add_members(model, nested)
          set_model_attributes(model, nested)
        end
      end

      # Declaration-level member hooks: single-line definitions, canonical
      # `value` members, mapping sections, class declarations, enum
      # member_fields and from_table all arrive as bare member hashes.
      def expand_declared_members(model, hash)
        expand_abstract_declaration(model, hash)
        expand_definition_text(model, hash)
        expand_value_declaration(model, hash)
        expand_value_set_declaration(model, hash)
        expand_mapping_section(model, hash)
        expand_class_declarations(model, hash)
        expand_enum_member_fields(model, hash)
        expand_from_table(model, hash)
        expand_operation_members(model, hash)
      end

      # Operation members arrive with grammar capture names
      # (`visibility_modifier`, `param_default`) and per-iteration
      # stereotype hashes; normalize to the model's field names.
      def expand_operation_members(model, hash)
        ops = hash.delete(:operations)
        return unless ops && model.class.attributes.key?(:operations)

        Array(ops.is_a?(Hash) ? [ops] : ops).each do |op|
          model.operations << build(:operation, normalize_operation_hash(op))
        end
      end

      def normalize_operation_hash(operation)
        operation = operation.dup
        if (vis = operation.delete(:visibility_modifier))
          operation[:visibility] = Transform::VISIBILITY_MAP.fetch(vis.to_s, 'public')
        end
        stereo = operation[:stereotype]
        if stereo
          items = stereo.is_a?(Array) ? stereo : [stereo]
          operation[:stereotype] = items.map { |x| x.is_a?(Hash) ? x[:stereotype].to_s : x.to_s }
        end
        params = operation[:owned_parameter]
        if params
          list = params.is_a?(Array) ? params : [params]
          operation[:owned_parameter] = list.map { |param| normalize_operation_param(param) }
        end
        operation
      end

      def normalize_operation_param(param)
        param = param.dup
        if (default = param.delete(:param_default))
          param[:default] = default.is_a?(Hash) ? default[:string].to_s : default.to_s
        end
        param
      end

      # RS 3001 §Definition single-line form (`definition "text"`) arrives
      # as a quoted-string capture; unwrap it for the entity's definition.
      # RS 3001 declaration modifiers: `abstract true` maps onto the
      # is_abstract field (the visibility declaration flows through the
      # generic attribute path).
      def expand_abstract_declaration(model, hash)
        value = hash.delete(:abstract)
        model.is_abstract = true if value.to_s == 'true' && model.class.attributes.key?(:is_abstract)
      end

      def expand_definition_text(model, hash)
        return unless hash.key?(:definition) && model.class.attributes.key?(:definition)

        model.definition = unquote(hash.delete(:definition))
      end

      # A mapping section arrives as a bare member hash
      # { format:, maps: [{ wire:, to: }] }; expand to one Mapping entry
      # per map line, each carrying the format, and strip the section keys
      def expand_mapping_section(model, hash)
        section = mapping_section_from(hash)
        return unless section

        section[:maps].to_a.each do |line|
          model.wire_mappings << build(:mapping,
                                       format: section[:format],
                                       wire: unquote(line[:wire]),
                                       to: unquote(line[:to]))
        end
      end

      def mapping_section_from(hash)
        return { format: unquote(hash[:format]), maps: hash.delete(:maps) } if hash.key?(:maps)

        hash.delete(:mappings)
      end

      # quoted_string captures nest their value under :string
      def unquote(value)
        value.is_a?(Hash) && value.key?(:string) ? value[:string] : value
      end

      # L5/L7 declaration members: string_format sections (class- or
      # models-level), derive lines, and enum member_fields blocks
      def expand_class_declarations(model, hash)
        if (section = hash.delete(:string_format))
          model.string_formats << build_string_format(section)
        end
        if (section = hash.delete(:default_string_formats))
          model.default_string_formats << build_string_format(section)
        end
        expand_class_namespace(model, hash)
        return unless (derived = hash.delete(:derived_field))

        model.derived_fields << build(:derived_field,
                                      name: derived[:name],
                                      type: unquote(derived[:type]))
      end

      # Issue #49: an in-class `namespace "uri" [prefix "p"]` line
      def expand_class_namespace(model, hash)
        decl = hash.delete(:class_namespace) or return

        model.xml_namespace = build(:namespace,
                                    uri: unquote(decl[:uri]),
                                    prefix: unquote(decl[:prefix]))
      end

      # L7a: from_table declares the enum's members as an artifact table
      # { from_table_name:, from_table_artifact? } — expansion happens at
      # compile time (deterministic materialization, no runtime data dep)
      def expand_from_table(model, hash)
        decl = hash.delete(:from_table_decl)
        return unless decl && model.is_a?(Enum)

        # the members repetition splits the declaration across iteration
        # hashes (name part, artifact part) — merge the parts
        parts = decl.is_a?(Array) ? decl : [decl]
        decl = parts.each_with_object({}) do |part, acc|
          acc.merge!(part) { |_key, _old, new_val| new_val }
        end
        model.from_table_name = unquote(decl[:from_table_name])
        model.from_table_artifact = unquote(decl[:artifact_table]) if decl[:artifact_table]
      end

      def expand_enum_member_fields(model, hash)
        decl = hash.delete(:member_fields_decl)
        return unless decl && model.is_a?(Enum)

        decl[:member_fields].to_a.each do |field|
          model.member_fields << build(:member_field,
                                       name: field[:name],
                                       type: unquote(field[:member_field_type]))
        end
      end

      def build_string_format(section)
        items = section[:items].to_a.to_h do |item|
          [item[:key].to_sym, unquote(item[:value])]
        end
        build(:string_format,
              format: unquote(section[:format]),
              artifact: items[:artifact],
              root: items[:root])
      end

      def ensure_collection(model, key)
        model.public_send(key) || begin
          model.public_send("#{key}=", [])
          model.public_send(key)
        end
      end

      def remap_filter_keys(hash, model)
        return unless model.is_a?(Document)

        hash[:show_filter] = build_view_filter(hash.delete(:show_list)) if hash.key?(:show_list)
        return unless hash.key?(:hide_list)

        hash[:hide_filter] = build_view_filter(hash.delete(:hide_list))
      end

      def build_view_filter(entity_names)
        ViewFilter.new(entity_names: Array(entity_names).map(&:to_s))
      end
    end
  end
end
