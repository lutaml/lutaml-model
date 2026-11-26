# frozen_string_literal: true

module Lutaml
  module Lml
    class ModelCompiler
      # Evaluates hydrated instances against their compiled
      # models (unknown attributes, enum membership, nesting).
      module Validation
        private

        def validate_instance(instance, errors, path = 'root')
          if instance.instance && Array(instance.attributes).empty?
            validate_instance(instance.instance, errors, "#{path}.instance")
            return
          end

          attrs = Array(instance.attributes)
          type_attr = attrs.find { |a| a.name == 'type' }
          type_name = type_attr ? type_attr.value.to_s : instance.type
          klass = @compiled[demodulize(type_name)]
          unless klass
            errors << "#{path}: unknown type '#{type_name}'"
            return
          end

          schema_attrs = klass.attributes.keys.map(&:to_s)
          present_attrs = attrs.map(&:name)
          schema_set = schema_attrs.to_set
          present_set = present_attrs.to_set

          unknown = present_set - schema_set - Set.new(%w[type])
          unknown.each do |name|
            errors << "#{path}.#{name}: attribute not defined on #{type_name}"
          end

          required = klass.attributes.values
                          .reject { |v| v.collection? || v.options.key?(:default) }
                          .to_set { |v| v.name.to_s }

          missing = required - present_set
          missing.each do |name|
            errors << "#{path}.#{name}: required attribute missing (cardinality min >= 1)"
          end

          attrs.each do |attr|
            next unless schema_attrs.include?(attr.name)

            attr_def = klass.attributes[attr.name.to_sym]
            next unless attr_def

            next unless attr_def.collection? && attr.instances.any?

            attr.instances.each_with_index do |nested, i|
              validate_instance(nested, errors, "#{path}.#{attr.name}[#{i}]")
            end
          end

          return unless instance.instance

          validate_instance(instance.instance, errors, "#{path}.instance")
        end
      end
    end
  end
end
