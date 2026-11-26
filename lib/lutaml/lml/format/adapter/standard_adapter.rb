# frozen_string_literal: true

module Lutaml
  module Lml
    module Format
      module Adapter
        # Serializes instance data to and from LML instance syntax on
        # behalf of the lutaml-model format registry (to_lml/from_lml on
        # compiled classes).
        class StandardAdapter < Document
          TYPE_KEY = "__type__"

          include Lutaml::Lml::Quoting

          def self.parse(data, _options = {})
            return data if data.is_a?(Hash)

            input = data.is_a?(IO) ? data : StringIO.new(data.to_s)
            doc = Lutaml::Lml.parse_document(input)
            instance_to_hash(doc.instance)
          end

          def to_lml(_options = {})
            attrs = @attributes.dup
            type_name = attrs.delete(TYPE_KEY) || "Data"
            body = hash_to_lml_body(attrs)
            "instance #{type_name} {\n#{body}\n}"
          end

          def self.instance_to_hash(instance)
            return nil unless instance

            hash = {}
            hash[TYPE_KEY] = instance.type if instance.type

            instance.each_attribute do |name, value, nested|
              if nested.any?
                hashes = nested.map { |i| instance_to_hash(i) }
                hash[name] = nested.one? ? hashes.first : hashes
              elsif value.is_a?(Array)
                hash[name] = value.map { |v| primitive_value(v) }
              elsif !value.nil?
                hash[name] = primitive_value(value)
              end
            end

            hash.merge!(instance_to_hash(instance.instance)) if instance.instance

            hash
          end

          def self.primitive_value(val)
            case val
            when TrueClass, FalseClass, Integer, Float then val
            else val.to_s
            end
          end
          private_class_method :primitive_value

          def hash_to_lml_body(hash, indent = 1)
            lines = []
            prefix = "  " * indent

            hash.each do |key, value|
              next if key == TYPE_KEY

              lines << format_value(prefix, key, value, indent)
            end

            lines.join("\n")
          end

          def format_key(key)
            quote_scalar(key)
          end

          def format_value(prefix, key, value, indent)
            key = format_key(key)
            return "#{prefix}#{key} = ref:(#{value[:reference]})" if reference_value?(value)

            case value
            when Array
              format_array(prefix, key, value, indent)
            when Hash
              format_nested(prefix, key, value, indent)
            when Float
              "#{prefix}#{key} = #{number_scalar(value)}"
            when TrueClass, FalseClass, Integer
              "#{prefix}#{key} = #{value}"
            else
              "#{prefix}#{key} = #{quote_value(value)}"
            end
          end

          def format_array(prefix, key, items, indent)
            elements = items.map do |item|
              if reference_value?(item)
                "  ref:(#{item[:reference]})"
              else
                case item
                when Hash
                  format_nested_instance(item, indent + 1)
                else
                  "  #{quote_value(item)}"
                end
              end
            end

            inner = elements.join(",\n")
            "#{prefix}#{key} = [\n#{inner}\n#{prefix}]"
          end

          def format_nested(prefix, key, hash, indent)
            type_name = hash.fetch(TYPE_KEY, "")
            inner = hash_to_lml_body(hash, indent + 1)
            type_clause = type_name.empty? ? "" : " #{type_name}"
            "#{prefix}#{key} = instance#{type_clause} {\n#{inner}\n#{prefix}}"
          end

          def format_nested_instance(hash, indent)
            prefix = "  " * indent
            type_name = hash.fetch(TYPE_KEY, "")
            inner = hash_to_lml_body(hash, indent + 1)
            type_clause = type_name.empty? ? "" : " #{type_name}"
            "#{prefix}instance#{type_clause} {\n#{inner}\n#{prefix}}"
          end

          # RS 3001 par. Value type: a `reference` map is the wire form of a
          # reference literal; it emits as `ref:(path)`, never as a nested
          # instance.
          def reference_value?(value)
            value.is_a?(Hash) && value.keys == [:reference]
          end

          def quote_value(val)
            return number_scalar(val) if val.is_a?(Float)
            return val.to_s if val.is_a?(Numeric) || val.is_a?(TrueClass) || val.is_a?(FalseClass)

            # RS 3001 §String values: escape backslash and double quote;
            # every value is representable in double quotes. A bare word
            # is only safe when the parser reads it back as the same
            # string — `null`, booleans, and digit-leading tokens are
            # data literals (and digit-led words do not re-parse).
            str = val.to_s
            return str if safe_bare_string?(str)

            quote_always(str)
          end

          private

          def safe_bare_string?(str)
            return false unless str.match?(Lutaml::Lml::Quoting::BARE_WORD)
            return false if str.match?(/\A(?:true|false|null)\z/)

            !str.match?(/\A\d/)
          end
        end
      end
    end
  end
end
