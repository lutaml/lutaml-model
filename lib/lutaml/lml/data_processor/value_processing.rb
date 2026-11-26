# frozen_string_literal: true

module Lutaml
  module Lml
    class DataProcessor
      module ValueProcessing
        VALUE_TYPE_KEYS = %i[instance list string boolean null key_value_map number float condition require].freeze

        VALUE_TYPE_HANDLERS = {
          instance: :handle_instance_value,
          list: :handle_list_value,
          string: :handle_string_value,
          boolean: :handle_boolean_value,
          null: :handle_null_value,
          key_value_map: :handle_key_value_map,
          number: :handle_number_value,
          float: :handle_float_value,
          condition: :handle_delegate_value,
          require: :handle_delegate_value
        }.freeze

        def process_value(value)
          return [] if value.nil?
          return process_hash_value(value) if value.is_a?(Hash)
          return process_array_value(value) if value.is_a?(Array)

          [value.class.to_s, value]
        end

        def process_list_value(list)
          process_typed_sequence(list)
        end

        def process_array_value(value)
          process_typed_sequence(value)
        end

        def handle_instance_value(_key, value)
          ['Instance', process_instance(value[:instance])]
        end

        def handle_list_value(_key, value)
          process_typed_sequence(value[:list])
        end

        def handle_string_value(_key, value)
          ['String', value[:string]]
        end

        def handle_boolean_value(_key, value)
          ['Boolean', value[:boolean] == 'true']
        end

        def handle_null_value(_key, _value)
          ['Null', nil]
        end

        def handle_key_value_map(_key, value)
          process_key_value_map(value[:key_value_map])
        end

        def handle_number_value(_key, value)
          ['Number', value[:number].to_i]
        end

        def handle_float_value(_key, value)
          ['Float', value[:float].to_f]
        end

        def handle_delegate_value(key, value)
          process_value(value[key])
        end

        private

        def process_hash_value(value)
          type_key = VALUE_TYPE_KEYS.find { |k| value.key?(k) }
          return ['Hash', value] unless type_key

          public_send(VALUE_TYPE_HANDLERS[type_key], type_key, value)
        end

        def process_typed_sequence(items)
          type = 'String'
          values = items.map do |item|
            item_type, item_value = process_value(item)
            type = item_type
            item_value
          end
          ["#{type}[]", values]
        end

        def process_key_value_map(kv_map)
          result = kv_map.each_with_object({}) do |kv, h|
            key, value = kv.values_at(:key, :value)
            h[key.to_sym] = process_value(value).last
          end
          ['Hash', result]
        end
      end
    end
  end
end
