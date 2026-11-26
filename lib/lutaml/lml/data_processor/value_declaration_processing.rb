# frozen_string_literal: true

module Lutaml
  module Lml
    class DataProcessor
      # RS 3001 §Value/§Attribute argument normalization: the canonical
      # `value` construct and the attribute `values` argument.
      module ValueDeclarationProcessing
        # `value <name> { block }` is the canonical enum member; the bare
        # identifier member is its documented shortcut. Normalize into the
        # member shape the shortcut produces: the value block's `definition`
        # lines become the member description and its attribute pairs become
        # member payload properties.
        def process_value_declaration(decl)
          inner = { name: unwrap_string(decl[:value_name]) }
          inner[:position] = decl[:position] if decl[:position]
          Array(decl[:members]).each do |member|
            normalize_value_member(inner, member)
          end
          { attributes: inner }
        end

        # `values <enum>` types the attribute with the named enum;
        # `values { v1, v2 }` carries an inline value set that the compiler
        # expands into an anonymous enum.
        def translate_values_argument(result)
          if result.key?(:value_set_ref)
            ref = unwrap_string(result.delete(:value_set_ref))
            result[:type] = ref unless result[:type]
          end
          return unless result.key?(:value_set)

          result[:value_set] = Array(result[:value_set][:items]).map { |item| unwrap_data_value(item[:item]) }
        end

        private

        def normalize_value_member(inner, member)
          if member.key?(:definition)
            (inner[:attributes] ||= []) << { name: 'description', type: unwrap_string(member[:definition]) }
          elsif member.key?(:instance)
            # The bare `instance { ... }` capture is the instance-body
            # hash; it must go through instance processing so its
            # members become attribute entries, not raw pairs.
            bodies = member[:instance].is_a?(Hash) ? [member[:instance]] : Array(member[:instance])
            bodies.each do |body|
              entry = body.is_a?(Hash) ? process_instance(body) : body
              (inner[:instances] ||= []) << entry
            end
          elsif member.key?(:attributes)
            (inner[:properties] ||= []) << member[:attributes]
          elsif member.key?(:key)
            (inner[:properties] ||= []) << extract_name_and_value(member)
          end
        end

        def unwrap_data_value(item)
          return item unless item.is_a?(Hash)

          item[:string] || item[:number] || item[:float] ||
            item[:boolean] || item[:name] || item
        end

        def unwrap_string(value)
          value.is_a?(Hash) && value.key?(:string) ? value[:string] : value
        end
      end
    end
  end
end
