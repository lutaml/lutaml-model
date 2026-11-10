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
      # attribute's members have no declared type, so each number is
      # spelled the one way the TS reader accepts as exact: an integer
      # spelling only for a safe integer (|n| <= 2**53-1), every other
      # float exactly as ECMAScript Number::toString spells it ("1e+21",
      # "1.5e-7", "0.1"). A hash member that cannot be held exactly (an
      # Integer beyond 2**53-1, a BigDecimal, -0.0, an integral float
      # beyond 2**53-1, NaN/Infinity, a value that is not JSON data, a
      # key collision or nesting deeper than 200) is refused. In
      # `data`, a non-integer hash number is a Number carrying that
      # spelling; `generate` writes it verbatim.
      #
      # Refused (RejectedError), never silently written: NaN/Infinity
      # (no wire form), mappings whose output this writer cannot type
      # (custom methods, delegates, keyed-collection and root mappings,
      # unions) and a value type whose native output is a
      # JSON number.
      module PortableJson
        PROFILE = "portable-exact-json-v1"
        MAX_SAFE_INTEGER = (2**53) - 1
        HASH_MAX_DEPTH = 200

        # A JSON number spelled exactly as written (see HashValue).
        class Number
          attr_reader :text

          def initialize(text)
            @text = text
          end

          def to_json(*)
            text
          end

          def ==(other)
            other.is_a?(Number) && other.text == text
          end
        end

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
          rescue ::JSON::JSONError => e
            # NaN/Infinity, a duplicate hash key, or nesting past the json
            # gem's limit of 100: no native output, so no portable output.
            raise RejectedError.new(:not_serializable, instance.class.name,
                                    "no portable wire form: native JSON output failed (#{e.message})")
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
            scalar(klass, type, native, value, location)
          end
        end

        def scalar(klass, type, native, value, location)
          return native unless type.is_a?(::Class)

          if type <= Lutaml::Model::Type::Hash
            hash_member(klass, value, location, 0)
          elsif type <= Lutaml::Model::Type::Integer
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

        # Rebuilds an in-memory `hash` attribute value as portable JSON data.
        def hash_member(klass, value, location, depth)
          if depth > HASH_MAX_DEPTH
            raise RejectedError.new(:not_serializable, klass.name,
                                    "#{location}: hash nesting is deeper than #{HASH_MAX_DEPTH}")
          end

          case value
          when nil, true, false then value
          when ::String then hash_string(klass, value, location)
          when ::Symbol then hash_string(klass, value.to_s, location)
          when ::Integer then hash_integer(klass, value, location)
          when ::Float then hash_float(klass, value, location)
          when ::Array
            value.each_with_index.map do |item, index|
              hash_member(klass, item, "#{location}/#{index}", depth + 1)
            end
          when ::Hash then hash_object(klass, value, location, depth)
          else
            raise RejectedError.new(:not_serializable, klass.name,
                                    "#{location}: #{value.class} in a hash has no portable spelling")
          end
        end

        def hash_object(klass, value, location, depth)
          value.each_with_object({}) do |(key, item), result|
            unless key.is_a?(::String) || key.is_a?(::Symbol)
              raise RejectedError.new(:not_serializable, klass.name,
                                      "#{location}: hash key #{RejectedError.show(key)} is not a string")
            end

            name = hash_string(klass, key.to_s, location)
            if result.key?(name)
              raise RejectedError.new(:not_serializable, klass.name,
                                      "#{location}: hash key #{RejectedError.show(name)} appears twice")
            end

            result[name] = hash_member(klass, item, "#{location}/#{name}", depth + 1)
          end
        end

        def hash_string(klass, value, location)
          return value if value.dup.force_encoding(::Encoding::UTF_8).valid_encoding?

          raise RejectedError.new(:not_serializable, klass.name,
                                  "#{location}: a hash string is not valid UTF-8")
        end

        def hash_integer(klass, value, location)
          return value if value.abs <= MAX_SAFE_INTEGER

          raise RejectedError.new(:not_serializable, klass.name,
                                  "#{location}: integer #{value} in a hash is beyond 2**53-1; " \
                                  "a JSON number cannot hold it exactly")
        end

        # Spells a float the way ECMAScript Number::toString does, from
        # Ruby's shortest round-trip digits. An integer spelling is only
        # accepted as a safe integer, so an integral float beyond 2**53-1
        # (1e20 is "100000000000000000000" in ECMAScript) and -0.0 (which
        # ECMAScript spells "0") have no exact spelling.
        def hash_float(klass, value, location)
          unless value.finite?
            raise RejectedError.new(:not_serializable, klass.name,
                                    "#{location}: a non-finite float in a hash has no JSON form")
          end
          if value.zero? && (1.0 / value).negative?
            raise RejectedError.new(:not_serializable, klass.name,
                                    "#{location}: -0.0 in a hash has no exact JSON spelling")
          end

          text = es_number(value)
          return Number.new(text) unless text.match?(/\A-?\d+\z/)
          return text.to_i if text.to_i.abs <= MAX_SAFE_INTEGER

          raise RejectedError.new(:not_serializable, klass.name,
                                  "#{location}: float #{text} in a hash is an integer spelling " \
                                  "beyond 2**53-1; a JSON number cannot hold it exactly")
        end

        # ECMAScript Number::toString (radix 10) of a finite, nonzero float.
        def es_number(value)
          match = value.abs.to_s.match(/\A(\d+)\.(\d+)(?:e([+-]\d+))?\z/)
          digits = match[1] + match[2]
          point = match[1].length + match[3].to_i
          lead = digits[/\A0*/].length
          digits = digits[lead..]
          point -= lead
          digits = digits.sub(/0+\z/, "")
          (value.negative? ? "-" : "") + es_digits(digits, point)
        end

        def es_digits(digits, point)
          count = digits.length
          if count <= point && point <= 21
            digits + ("0" * (point - count))
          elsif point.positive? && point <= 21
            "#{digits[0, point]}.#{digits[point..]}"
          elsif point <= 0 && point > -6
            "0.#{'0' * -point}#{digits}"
          else
            exponent = point - 1
            mantissa = count == 1 ? digits : "#{digits[0]}.#{digits[1..]}"
            "#{mantissa}e#{exponent.negative? ? '-' : '+'}#{exponent.abs}"
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
