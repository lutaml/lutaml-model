# frozen_string_literal: true

module Lutaml
  module Yamls
    module Adapter
      class Transform < Lutaml::KeyValue::Transform
        def data_to_model(data, format, options = {})
          mappings = defined_mappings_for(:yamls) || mappings_for(:yaml,
                                                                  lutaml_register)

          if mappings.is_a?(Mapping) && mappings.yamls_sequence
            data_to_model_with_sequence(data, format, mappings.yamls_sequence,
                                        options)
          else
            super(data, format, options.merge(mappings: mappings))
          end
        end

        def model_to_data(instance, _format, options = {})
          mappings = defined_mappings_for(:yamls) || mappings_for(:yaml,
                                                                  lutaml_register)

          if mappings.is_a?(Mapping) && mappings.yamls_sequence
            model_to_data_with_sequence(instance, mappings.yamls_sequence)
          else
            defined = defined_mappings_for(:yamls) || mappings_for(:yaml,
                                                                   lutaml_register)
            super(instance, :yaml, options.merge(mappings: defined))
          end
        end

        private

        def data_to_model_with_sequence(data_array, format, sequence, options)
          register = lutaml_register
          child_register = Lutaml::Model::Register.resolve_for_child(
            model_class, register
          )

          instance = if model_class.include?(Lutaml::Model::Serialize)
                       model_class.new(lutaml_register: child_register)
                     else
                       model_class.new
                     end
          root_and_parent_assignment(instance, options)

          sequence.rules.each do |rule|
            docs = extract_docs_for_rule(data_array, rule)
            next if docs.nil?
            next if docs.is_a?(Array) && docs.empty?

            if rule.singular?
              doc = docs.is_a?(Array) ? docs.first : docs
              value = deserialize_single_doc(doc, rule.type, format,
                                             register, instance)
              rule.assign_value(instance, value)
            else
              values = docs.map do |doc|
                deserialize_single_doc(doc, rule.type, format, register,
                                       instance)
              end
              rule.assign_value(instance, values)
            end
          end

          instance
        end

        def extract_docs_for_rule(data_array, rule)
          size = data_array.size
          return nil if size.zero?

          case rule.position
          when Integer
            idx = rule.position.negative? ? rule.position + size : rule.position
            data_array[idx]
          when Range
            start_idx = rule.position.begin.negative? ? rule.position.begin + size : rule.position.begin
            end_idx = rule.position.end
            end_idx = size - 1 if end_idx.nil?
            end_idx = end_idx + size if end_idx.negative?
            end_idx = size - 1 if end_idx > size - 1
            start_idx = 0 if start_idx.negative?
            return nil if start_idx > end_idx

            data_array[start_idx..end_idx]
          end
        end

        def deserialize_single_doc(doc, type, _format, register, parent)
          transformer = Lutaml::Model::Config.transformer_for(:yaml)
          transformer.data_to_model(
            type, doc, :yaml,
            register: register,
            lutaml_parent: parent,
            lutaml_root: parent.lutaml_root || parent
          )
        end

        def model_to_data_with_sequence(instance, sequence)
          results = []

          sequence.rules.each do |rule|
            value = rule.read_value(instance)
            next if value.nil?

            if rule.singular?
              results << serialize_single_model(value)
            else
              value.each { |item| results << serialize_single_model(item) }
            end
          end

          results
        end

        def serialize_single_model(item)
          transformer = Lutaml::Model::Config.transformer_for(:yaml)
          transformer.model_to_data(item.class, item, :yaml)
        end
      end
    end
  end
end
