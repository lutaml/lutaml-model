# frozen_string_literal: true

module Lutaml
  module Lml
    class DataProcessor
      # Normalizes attribute entries from the parse tree: merges
      # comma-form groups, extracts names/types/values, and applies the
      # nested attribute/property structure.
      module AttributeProcessing
        EXCLUDED_PASS_THROUGH_KEYS = %i[key value comments add attributes properties type_literal].freeze

        def process_attributes(obj)
          case obj
          when Array then process_attributes_array(obj)
          when Hash then process_attributes_hash(obj)
          end
        end

        def process_attributes_array(obj)
          return [] if obj.empty?
          return obj.map { |item| process_attributes(item) } unless named_attribute_entries?(obj)
          return merge_named_entries(obj) unless single_key_hashes?(obj)

          obj.each_with_object({}) { |item, hash| append_uniform_entry(hash, item) }
        end

        def append_uniform_entry(hash, item)
          hash[:properties] ||= []
          if item.key?(:properties)
            hash[:properties] << process_attributes(item[:properties])
          else
            hash.merge!(process_attributes(item))
          end
        end

        # Attribute-definition groups split across capture depths (e.g. the
        # comma form: {name, type} beside a nested {value_set}) combine into
        # one attribute entry. Key/value pair lists (import/export maps)
        # carry :key and are never merged.
        def named_attribute_entries?(obj)
          obj.any? { |e| e.is_a?(Hash) && e.key?(:name) } &&
            obj.all? { |e| e.is_a?(Hash) && !e.key?(:key) }
        end

        COLLECTION_KEYS = %i[properties attributes instances].freeze

        def merge_named_entries(obj)
          obj.each_with_object({}) do |item, hash|
            process_attributes(item).each do |key, value|
              hash[key] = merge_attribute_value(hash[key], key, value)
            end
          end
        end

        def merge_attribute_value(existing, key, value)
          return merge_collection_value(existing, value) if COLLECTION_KEYS.include?(key)
          return existing + value if existing.is_a?(Array) && value.is_a?(Array)

          value
        end

        def merge_collection_value(existing, value)
          current = if existing.is_a?(Array)
                      existing
                    else
                      (existing ? [existing] : [])
                    end
          current + (value.is_a?(Array) ? value : [value])
        end

        def process_attributes_hash(obj)
          result = extract_name_and_value(obj)
          convert_instance_type(result)
          result[:extended] = !obj[:add].nil? if obj.key?(:add)
          result[:literal] = true if obj.key?(:type_literal)
          apply_nested_attributes(result, obj)
          apply_remaining_keys(result, obj)
          translate_values_argument(result)
          result
        end

        def single_key_hashes?(arr)
          arr.all? { |e| e.is_a?(Hash) && e.keys.size == 1 }
        end

        def extract_name_and_value(obj)
          result = {}
          result[:name] = strip_argument_colon(obj[:key]) if obj.key?(:key)

          if obj.key?(:comments)
            result[:name] = 'Comment'
            result[:value] = process_value(obj[:comments]).last
          elsif obj.key?(:value)
            result[:type], result[:value] = process_value(obj[:value])
          end

          result
        end

        def convert_instance_type(result)
          return unless result[:type]&.start_with?('Instance')

          value = result.delete(:value)
          result[:instances] = value.is_a?(Array) ? value : [value]
          result.delete(:type)
        end

        def apply_nested_attributes(result, obj)
          result[:attributes] = process_attributes(obj[:attributes]) if obj.key?(:attributes)
          result[:properties] = process_attributes(obj[:properties]) if obj.key?(:properties)
        end

        def apply_remaining_keys(result, obj)
          obj.each do |key, value|
            next if EXCLUDED_PASS_THROUGH_KEYS.include?(key)

            value = strip_argument_colon(value) if key == :name
            result[key] = value unless result.key?(key)
          end
        end

        # `default: "Clear"` uses the colon separator (RS 3001 §Attribute);
        # the colon lands in the captured name and must not. A quoted key
        # is verbatim, so a trailing colon there is content.
        def strip_argument_colon(name)
          return name[:string] if name.is_a?(Hash) && name.key?(:string)

          name.to_s.sub(/:\z/, "")
        end
      end
    end
  end
end
