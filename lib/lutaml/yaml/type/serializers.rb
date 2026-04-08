# frozen_string_literal: true

module Lutaml
  module Yaml
    module Type
      # Registers YAML-specific type serializers for types that need
      # custom to_yaml / from_yaml behavior beyond the default.
      module Serializers
        module_function

        def register_all!
          v = Lutaml::Model::Type::Value

          # String — from_yaml delegates to cast
          v.register_format_type_serializer(
            :yaml, Lutaml::Model::Type::String,
            from: ->(val) { Lutaml::Model::Type::String.cast(val) }
          )

          # Time — ISO8601 string
          v.register_format_type_serializer(
            :yaml, Lutaml::Model::Type::Time,
            to: ->(inst) { inst.value&.iso8601.to_s }
          )

          # DateTime — ISO8601 string
          v.register_format_type_serializer(
            :yaml, Lutaml::Model::Type::DateTime,
            to: ->(inst) { inst.value&.iso8601.to_s }
          )

          # TimeWithoutDate — HH:MM:SS string
          v.register_format_type_serializer(
            :yaml, Lutaml::Model::Type::TimeWithoutDate,
            to: ->(inst) { inst.value&.strftime("%H:%M:%S").to_s }
          )

          # Date — ISO8601 string
          v.register_format_type_serializer(
            :yaml, Lutaml::Model::Type::Date,
            to: ->(inst) { inst.value&.iso8601.to_s }
          )

          # Decimal — F format string
          v.register_format_type_serializer(
            :yaml, Lutaml::Model::Type::Decimal,
            to: ->(inst) { inst.value&.to_s("F") }
          )

          # Reference — key
          v.register_format_type_serializer(
            :yaml, Lutaml::Model::Type::Reference,
            to: lambda(&:key),
            from: ->(val) { Lutaml::Model::Type::Reference.cast(val) }
          )
        end
      end
    end
  end
end
