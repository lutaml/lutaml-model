# frozen_string_literal: true

module Lutaml
  module Json
    module Type
      # Registers JSON-specific type serializers for types that need
      # custom to_json / from_json behavior beyond the default.
      module Serializers
        module_function

        def register_all!
          v = Lutaml::Model::Type::Value

          # String — from_json delegates to cast
          v.register_format_type_serializer(
            :json, Lutaml::Model::Type::String,
            from: ->(val) { Lutaml::Model::Type::String.cast(val) }
          )

          # Time — ISO8601 with fractional seconds handling
          v.register_format_type_serializer(
            :json, Lutaml::Model::Type::Time,
            to: lambda { |inst|
              return nil unless inst.value

              if inst.value.subsec.zero?
                inst.value.iso8601
              else
                inst.value.iso8601(6).sub(/(\.\d{3})0{3}([+-])/, '\1\2')
              end
            }
          )

          # DateTime — RFC3339 (ISO8601 with timezone)
          v.register_format_type_serializer(
            :json, Lutaml::Model::Type::DateTime,
            to: lambda { |inst|
              return nil unless inst.value

              Lutaml::Model::Type::DateTime.format_datetime_iso8601(inst.value)
            }
          )

          # Date — ISO8601 with optional timezone
          v.register_format_type_serializer(
            :json, Lutaml::Model::Type::Date,
            to: ->(inst) { Lutaml::Model::Type::Date.serialize(inst.value) }
          )

          # TimeWithoutDate — HH:MM:SS format
          v.register_format_type_serializer(
            :json, Lutaml::Model::Type::TimeWithoutDate,
            to: ->(inst) { Lutaml::Model::Type::TimeWithoutDate.serialize(inst.value) }
          )

          # Symbol — :symbol: format
          v.register_format_type_serializer(
            :json, Lutaml::Model::Type::Symbol,
            to: ->(inst) { ":#{inst.value}:" }
          )

          # Reference — key
          v.register_format_type_serializer(
            :json, Lutaml::Model::Type::Reference,
            to: lambda(&:key),
            from: ->(val) { Lutaml::Model::Type::Reference.cast(val) }
          )
        end
      end
    end
  end
end
