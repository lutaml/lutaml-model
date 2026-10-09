# frozen_string_literal: true

module Lutaml
  module Xml
    module Type
      # Registers XML-specific type serializers for all types that need
      # custom to_xml / from_xml behavior beyond the default (return value).
      module Serializers
        module_function

        # The default :xml String serializer is the identity for String
        # values. Attribute#serialize_value fast-paths String→String
        # through an identity comparison with this exact proc, so a
        # consumer override of the serializer disables that fast path
        # automatically.
        STRING_XML_TO = ->(inst) { inst.value&.to_s }.freeze

        def register_all!
          v = Lutaml::Model::Type::Value

          # String — value&.to_s
          v.register_format_type_serializer(
            :xml, Lutaml::Model::Type::String,
            to: STRING_XML_TO,
            from: ->(val) { Lutaml::Model::Type::String.cast(val) }
          )

          # Float — value.to_s
          v.register_format_type_serializer(
            :xml, Lutaml::Model::Type::Float,
            to: ->(inst) { inst.value.to_s }
          )

          # Boolean — value.to_s
          v.register_format_type_serializer(
            :xml, Lutaml::Model::Type::Boolean,
            to: ->(inst) { inst.value.to_s }
          )

          # Time — ISO8601 with fractional seconds handling
          v.register_format_type_serializer(
            :xml, Lutaml::Model::Type::Time,
            to: lambda { |inst|
              return nil unless inst.value

              if inst.value.subsec.zero?
                inst.value.iso8601
              else
                inst.value.iso8601(6).sub(/(\.\d{3})0{3}([+-])/, '\1\2')
              end
            }
          )

          # DateTime — ISO8601 with Z for UTC
          v.register_format_type_serializer(
            :xml, Lutaml::Model::Type::DateTime,
            to: lambda { |inst|
              return nil unless inst.value

              result = Lutaml::Model::Type::DateTime.format_datetime_iso8601(inst.value)
              inst.value.offset.zero? ? result.sub(/\+00:00$/, "Z") : result
            }
          )

          # Date — ISO8601 with Z for UTC
          v.register_format_type_serializer(
            :xml, Lutaml::Model::Type::Date,
            to: lambda { |inst|
              return nil unless inst.value

              result = Lutaml::Model::Type::Date.serialize(inst.value)
              result = result.sub(/\+00:00$/, "Z") if result.include?("+00:00")
              result
            }
          )

          # TimeWithoutDate — delegates to self.class.serialize
          v.register_format_type_serializer(
            :xml, Lutaml::Model::Type::TimeWithoutDate,
            to: ->(inst) { Lutaml::Model::Type::TimeWithoutDate.serialize(inst.value) }
          )

          # Symbol — :symbol: format
          v.register_format_type_serializer(
            :xml, Lutaml::Model::Type::Symbol,
            to: ->(inst) { ":#{inst.value}:" }
          )

          # Hash — value (pass-through)
          v.register_format_type_serializer(
            :xml, Lutaml::Model::Type::Hash,
            to: lambda(&:value)
          )

          # Reference — key&.to_s
          v.register_format_type_serializer(
            :xml, Lutaml::Model::Type::Reference,
            to: ->(inst) { inst.key&.to_s },
            from: ->(val) { Lutaml::Model::Type::Reference.cast(val) }
          )
        end
      end
    end
  end
end
