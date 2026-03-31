# frozen_string_literal: true

module Lutaml
  module Toml
    module Type
      # Registers TOML-specific type serializers for types that need
      # custom to_toml / from_toml behavior beyond the default.
      module Serializers
        module_function

        def register_all!
          v = Lutaml::Model::Type::Value

          # String — value&.to_s
          v.register_format_type_serializer(
            :toml, Lutaml::Model::Type::String,
            to: ->(inst) { inst.value&.to_s },
            from: ->(val) { Lutaml::Model::Type::String.cast(val) }
          )

          # Boolean — value.to_s
          v.register_format_type_serializer(
            :toml, Lutaml::Model::Type::Boolean,
            to: ->(inst) { inst.value.to_s }
          )

          # Time — HH:MM:SS.mmm format
          v.register_format_type_serializer(
            :toml, Lutaml::Model::Type::Time,
            to: ->(inst) { inst.value&.strftime("%H:%M:%S.%L") }
          )

          # DateTime — RFC3339 format
          v.register_format_type_serializer(
            :toml, Lutaml::Model::Type::DateTime,
            to: lambda { |inst|
              return nil unless inst.value

              Lutaml::Model::Type::DateTime.format_datetime_iso8601(inst.value)
            }
          )

          # TimeWithoutDate — HH:MM:SS.mmm with milliseconds
          v.register_format_type_serializer(
            :toml, Lutaml::Model::Type::TimeWithoutDate,
            to: ->(inst) { inst.value.strftime("%H:%M:%S.%L") }
          )

          # Symbol — :symbol: format
          v.register_format_type_serializer(
            :toml, Lutaml::Model::Type::Symbol,
            to: ->(inst) { ":#{inst.value}:" }
          )

          # Reference — key&.to_s
          v.register_format_type_serializer(
            :toml, Lutaml::Model::Type::Reference,
            to: ->(inst) { inst.key&.to_s },
            from: ->(val) { Lutaml::Model::Type::Reference.cast(val) }
          )
        end
      end
    end
  end
end
