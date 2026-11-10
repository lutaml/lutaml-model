# frozen_string_literal: true

require "bigdecimal"
require "json"

module Lutaml
  module Model
    module Lml
      # Writer for the `portable-exact-json-v1` wire profile
      # (lutaml-model#1033), the profile the TS and Rust codecs read.
      #
      # `Serializable#to_json` writes `ruby-native-v1`: plain JSON numbers.
      # This opt-in writer starts from that native output and re-spells
      # only the values whose exact value a JSON number cannot carry, by
      # the declared attribute type:
      #
      # * integer, positive_integer, non_negative_integer: a decimal
      #   string ("9007199254740993"), never a JSON number.
      # * decimal: a plain decimal string without exponent ("1.5", never
      #   BigDecimal's "0.15e1"); signed zero is kept ("-0.0").
      # * float: the canonical float wire string (DocumentValidator
      #   .float_wire: "0.1", "1.0e20", "-0.0").
      #
      # Booleans, strings, nil, nested models and collections keep their
      # native JSON shape. Key order is the native order. A `hash`
      # attribute is carried as-is: its members have no declared type.
      #
      # Refused (RejectedError), never silently written: NaN/Infinity
      # (no wire form), mappings whose output this writer cannot type
      # (custom methods, delegates, keyed-collection and root mappings,
      # unions) and a value type whose native output is a
      # JSON number.
      module PortableJson
        PROFILE = "portable-exact-json-v1"

        module_function

        # @param instance [Lutaml::Model::Serializable]
        # @param pretty [Boolean] JSON.pretty_generate instead of generate
        # @return [String] the instance as portable-exact-json-v1 text
        def generate(instance, pretty: false)
          data = self.data(instance)
          pretty ? ::JSON.pretty_generate(data) : ::JSON.generate(data)
        end

        # @return [Hash] the portable wire document (string-keyed)
        def data(instance)
          unless instance.is_a?(Lutaml::Model::Serialize)
            raise RejectedError.new(:not_serializable, instance.class.name,
                                    "portable JSON needs a Serializable instance")
          end

          native = begin
            ::JSON.parse(instance.to_json)
          rescue ::JSON::GeneratorError => e
            raise RejectedError.new(:not_serializable, instance.class.name,
                                    "a non-finite float has no portable wire form (#{e.message})")
          end
          portable_model(instance, native, "")
        end

        def portable_model(instance, native, location)
          klass = instance.class
          return native unless native.is_a?(::Hash)

          mapping = klass.mappings_for(:json, instance.lutaml_register)
          reject_mapping!(klass, mapping)
          mapping.mappings.each do |rule|
            reject_rule!(klass, rule)
            key = Array(rule.name).map(&:to_s).find { |name| native.key?(name) }
            next unless key

            attribute = klass.attributes(instance.lutaml_register)[rule.to]
            next unless attribute

            native[key] = portable_value(klass, attribute, instance.public_send(rule.to),
                                         native[key], "#{location}/#{key}")
          end
          native
        end

        def portable_value(klass, attribute, value, native, location)
          return native if native.nil?

          if attribute.collection?
            return native unless native.is_a?(::Array)

            items = Array(value)
            unless items.size == native.size
              raise RejectedError.new(:not_serializable, klass.name,
                                      "#{location}: collection size differs from its native output")
            end

            return native.each_with_index.map do |item, index|
              portable_item(klass, attribute, items[index], item, "#{location}/#{index}")
            end
          end

          portable_item(klass, attribute, value, native, location)
        end

        def portable_item(klass, attribute, value, native, location)
          return native if native.nil?

          if attribute.union?
            raise RejectedError.new(:unsupported_type, klass.name,
                                    "#{location}: union attributes have no portable spelling")
          end

          type = attribute.type
          if value.is_a?(Lutaml::Model::Serialize)
            portable_model(value, native, location)
          else
            scalar(klass, type, native, location)
          end
        end

        def scalar(klass, type, native, location)
          return native unless type.is_a?(::Class)

          if type <= Lutaml::Model::Type::Integer
            integer(klass, native, location)
          elsif type <= Lutaml::Model::Type::Decimal
            decimal(klass, native, location)
          elsif type <= Lutaml::Model::Type::Float
            float(klass, native, location)
          elsif native.is_a?(::Numeric)
            raise RejectedError.new(:not_serializable, klass.name,
                                    "#{location}: #{type} writes a JSON number; the portable profile " \
                                    "carries numbers only as integer, decimal or float strings")
          else
            native
          end
        end

        def integer(klass, native, location)
          return native.to_s if native.is_a?(::Integer)

          unsupported!(klass, "integer", native, location)
        end

        def decimal(klass, native, location)
          number = case native
                   when ::String then BigDecimal(native)
                   when ::Integer, ::Float then BigDecimal(native.to_s)
                   else unsupported!(klass, "decimal", native, location)
                   end
          unless number.finite?
            raise RejectedError.new(:not_serializable, klass.name,
                                    "#{location}: a non-finite decimal has no portable wire form")
          end

          # `to_s("F")` never uses an exponent; it spells -0 as "-0.0".
          number.to_s("F")
        rescue ::ArgumentError
          unsupported!(klass, "decimal", native, location)
        end

        def float(klass, native, location)
          return unsupported!(klass, "float", native, location) unless native.is_a?(::Numeric)

          DocumentValidator.float_wire(native)
        rescue ::ArgumentError
          raise RejectedError.new(:not_serializable, klass.name,
                                  "#{location}: a non-finite float has no portable wire form")
        end

        def unsupported!(klass, kind, native, location)
          raise RejectedError.new(:not_serializable, klass.name,
                                  "#{location}: #{kind} value #{RejectedError.show(native)} " \
                                  "has no portable spelling")
        end

        def reject_mapping!(klass, mapping)
          if mapping.respond_to?(:root_name) && mapping.root_name
            reject!(klass, "a root key")
          elsif mapping.respond_to?(:unmapped_attribute) && mapping.unmapped_attribute
            reject!(klass, "map_all")
          elsif mapping.respond_to?(:instance_mapping?) && mapping.instance_mapping?
            reject!(klass, "map_instances/map_key/map_value")
          end
        end

        def reject_rule!(klass, rule)
          reject!(klass, "custom methods on #{rule.name}") if rule.custom_methods.to_h.any?
          reject!(klass, "a delegate on #{rule.name}") if rule.delegate
          reject!(klass, "child_mappings on #{rule.name}") if present_hash?(rule.child_mappings)
          reject!(klass, "root_mappings on #{rule.name}") if present_hash?(rule.root_mappings)
        end

        def present_hash?(value)
          value.is_a?(::Hash) && !value.empty?
        end

        def reject!(klass, what)
          raise RejectedError.new(:unsupported_mapping, klass.name,
                                  "portable JSON cannot type #{what}")
        end
      end
    end
  end
end
