# frozen_string_literal: true

module Lutaml
  module Lml
    class ModelCompiler
      # Builds typed instances from parsed instance documents
      # against the compiled class set.
      module Hydration
        private

        def hydrate_instance(instance)
          inner = instance.instance
          return hydrate_instance(inner) if inner && Array(instance.attributes).empty?

          type_name = resolve_instance_type(instance)
          klass = @compiled[type_name]
          return hydrate_as_untyped(instance, type_name) unless klass

          attrs = extract_instance_attributes(instance, klass)
          klass.new(**attrs)
        end

        # An inline map's cargo is {key_value_map: [{key:, value:}, ...]} with
        # literal-shaped keys/values ({string: ..}, {number: ..}, {boolean: ..});
        # materialize it as a plain Hash (issue #17: maps hydrate as data).

        # An inline map's cargo is {key_value_map: [{key:, value:}, ...]} with
        # literal-shaped keys/values ({string: ..}, {number: ..}, {boolean: ..});
        # materialize it as a plain Hash (issue #17: maps hydrate as data).
        def hydrate_map_cargo(cargo)
          cargo[:key_value_map].to_h do |pair|
            [hydrate_scalar(pair[:key]).to_s, hydrate_scalar(pair[:value])]
          end
        end

        def hydrate_scalar(literal)
          literal = literal.value if literal.respond_to?(:value)
          literal.is_a?(Hash) ? literal.values.first : literal
        end

        def resolve_instance_type(instance)
          # L6: the explicit isa keyword is the type override; a `type`
          # attribute is ordinary data (pubid's identifier-kind field)
          return demodulize(instance.isa.to_s) if instance.isa

          demodulize(instance.type.to_s)
        end

        def demodulize(name)
          name.split('::').last.to_s
        end

        def hydrate_as_untyped(instance, type_name)
          { _name: type_name, **extract_raw_attributes(instance) }
        end

        def extract_raw_attributes(instance)
          instance.each_attribute.with_object({}) do |(name, value, nested), hash|
            hash[name.to_sym] = resolve_instance_value(value, nested)
          end
        end

        def extract_instance_attributes(instance, klass)
          schema_keys = klass.attributes.keys.to_set
          instance.each_attribute.with_object({}) do |(name, value, nested), hash|
            key = name.to_sym
            next unless schema_keys.include?(key)

            hash[key] = resolve_instance_value(value, nested, klass.attributes[key])
          end
        end

        def resolve_instance_value(value, nested, attr_def = nil)
          value = value.value if value.respond_to?(:value)
          return hydrate_map_cargo(value) if value.is_a?(Hash) && value.key?(:key_value_map)

          if nested.any?
            # A scalar attribute with a single nested instance hydrates to
            # the object itself; the declaration is the truth (issue #17).
            return hydrate_typed(nested.first, attr_def) if !attr_def&.collection && nested.one?

            nested.map { |i| hydrate_typed(i, attr_def) }
          # The Array guard must run before the enum branch: an array
          # value under an enum-typed attribute stays a raw array.
          # rubocop:disable Lint/DuplicateBranch
          elsif value.is_a?(Array)
            value
          elsif (enum_class = attr_def && enum_class_for(attr_def.type))
            value_name = enum_value_name(value.to_s)
            description = enum_class.values
                                    .find { |v| v.name == value_name }&.description
            enum_class.new(value: value_name, description: description)
          elsif !value.nil?
            value
            # rubocop:enable Lint/DuplicateBranch
          end
        end

        # An untyped nested instance takes the enclosing attribute's type;
        # hydrate_as_untyped would otherwise emit a raw hash polluted with
        # a `_name` key, which also defeats union member key-coverage.

        # An untyped nested instance takes the enclosing attribute's type;
        # hydrate_as_untyped would otherwise emit a raw hash polluted with
        # a `_name` key, which also defeats union member key-coverage.
        def hydrate_typed(instance, attr_def)
          return hydrate_instance(instance) if instance.isa || !instance.type.to_s.empty?

          type = attr_def&.type
          return hydrate_instance(instance) unless type.is_a?(Class)

          if type.include?(Lutaml::Model::Serialize)
            type.new(**extract_instance_attributes(instance, type))
          elsif type == Lutaml::Model::Type::Union
            extract_raw_attributes(instance)
          else
            hydrate_instance(instance)
          end
        end
      end
    end
  end
end
