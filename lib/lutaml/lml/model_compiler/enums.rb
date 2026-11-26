# frozen_string_literal: true

module Lutaml
  module Lml
    class ModelCompiler
      # Compiles LML enums into Serializable subclasses with member
      # payloads, table-driven expansion, and value accessors.
      module Enums
        EnumValue = Struct.new(:name, :description, :payload)

        private

        def compile_enum(enum_def)
          name = enum_def.name.to_s
          expand_from_table(enum_def)
          values = extract_enum_values(enum_def)

          payload_fields = Array(enum_def.member_fields).map(&:name).map(&:to_s)
          value_names = values.map { |v| v.name.to_s }
          compiled_klass = Class.new(Lutaml::Model::Serializable) do
            attribute :value, :string, values: value_names, default: values.first.name
            attribute :description, :string
            payload_fields.each do |field|
              attribute field.to_sym, :string
            end

            define_method(:to_s) { value }
          end

          values.each do |value|
            accessor = value.name.to_s.gsub(/[^a-zA-Z0-9_]/, '_')
            compiled_klass.define_singleton_method(accessor) do
              new({ value: value.name, description: value.description }.merge(value.payload || {}))
            end
          end
          compiled_klass.define_singleton_method(:values) { values }

          @enum_names << name
          @enum_classes[name] = compiled_klass
          register(name, compiled_klass)
        end

        # Builds a compiled Serializable subclass from a class or data-type
        # definition: declares attributes and stashes forward-referenced
        # attributes for post-registration resolution.

        # RS 3001 §Attribute: `values { v1, v2 }` expands into an anonymous
        # enum baked from the inline set; the attribute is typed with it.
        def resolve_values_type(klass_def, attr)
          return attr.type.to_s unless attr.value_set&.any?

          enum_name = anonymous_enum_name(klass_def.name, attr.name)
          members = attr.value_set.map { |v| ::Lutaml::Lml::TopElementAttribute.new(name: v.to_s) }
          compile_enum(::Lutaml::Lml::Enum.new(name: enum_name, attributes: members))
          enum_name
        end

        def anonymous_enum_name(class_name, attr_name)
          base = class_name.to_s.split('::').last
          attr_part = attr_name.to_s.split('_').map(&:capitalize).join
          "#{base}#{attr_part}Values"
        end

        # L7a point 3: from_table members are baked at compile time — the
        # artifact table's rows become the values, validated against the
        # declared member_fields (unknown field = error; missing = nil).
        # The member name comes from the row's "name" column.
        def expand_from_table(enum_def)
          return unless enum_def.from_table_name

          rows = artifact_table_rows(enum_def)
          known = Array(enum_def.member_fields).map { |f| f.name.to_s }
          rows.each do |row|
            row = row.transform_keys(&:to_s)
            member_name = row.fetch('name')
            unknown = row.keys - known - ['name']
            if unknown.any?
              raise ArgumentError,
                    "enum #{enum_def.name}: table row #{member_name.inspect} has " \
                    "undeclared fields #{unknown.inspect} (declared: #{known.inspect})"
            end
            payload = row.slice(*known).compact
            enum_def.attributes << TopElementAttribute.new(
              name: member_name,
              properties: payload.map do |field, value|
                TopElementAttribute.new(name: field, value: value)
              end,
            )
          end
        end

        def artifact_table_rows(enum_def)
          reference = enum_def.from_table_artifact || @default_artifact
          path = artifact_path_for(reference.to_s)
          unless path
            raise ArgumentError,
                  "enum #{enum_def.name}: from_table artifact #{reference.inspect} not found"
          end

          envelope = JSON.parse(File.read(path))
          table = envelope['tables'].to_h[enum_def.from_table_name]
          unless table
            raise ArgumentError,
                  "enum #{enum_def.name}: table #{enum_def.from_table_name.inspect} " \
                  "not found in artifact #{reference.inspect}"
          end

          table['rows'].to_a
        end

        def extract_enum_values(enum_def)
          member_fields = Array(enum_def.member_fields).map do |f|
            [f.name.to_s, f.type.to_s]
          end
          enum_def.attributes.map do |attr|
            description = member_description(attr)
            payload = extract_member_payload(attr)
            validate_member_payload(enum_def, attr, payload, member_fields)
            EnumValue.new(attr.name.to_s, description, payload)
          end
        end

        # The member description rides a nested attribute named `description`
        # (bare-member form) or `definition` (RS 3001 `value` blocks); both
        # spellings are accepted.

        # The member description rides a nested attribute named `description`
        # (bare-member form) or `definition` (RS 3001 `value` blocks); both
        # spellings are accepted.
        def member_description(attr)
          nested = Array(attr.attributes).find do |n|
            %w[description definition].include?(n.name.to_s)
          end
          text = nested&.type || nested&.definition || nested&.value
          text.is_a?(Hash) && text.key?(:string) ? text[:string] : text
        end

        # L7a: per-member payload lines ride the keyword-attribute
        # properties (`abbreviation = "WD"`)

        # L7a: per-member payload lines ride the keyword-attribute
        # properties (`abbreviation = "WD"`)
        def extract_member_payload(attr)
          Array(attr.properties).to_h { |p| [p.name.to_s, p.value&.to_s] }
        end

        def validate_member_payload(enum_def, attr, payload, member_fields)
          known = member_fields.map(&:first)
          unknown = payload.keys - known
          return unless unknown.any?

          raise ArgumentError,
                "enum #{enum_def.name}: member #{attr.name} has undeclared " \
                "payload fields #{unknown.inspect} (declared: #{known.inspect})"
        end

        def enum_class_for(type)
          type.is_a?(Class) && @enum_classes.value?(type) and return type
        end

        def enum_value_name(raw)
          raw.split('::').last
        end

        # L7b: derived fields declare existence + type; computation is
        # bound by the binder from artifact derive specs. The attribute
        # participates in mappings like any other (relaton consumes URNs
        # from model JSON).
      end
    end
  end
end
