# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Templates
        module SimpleType
          extend self
          attr_accessor :simple_types

          SUPPORTED_DATA_TYPES = {
            nonNegativeInteger: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\+?[0-9]+/ } },
            positiveInteger: { class_name: "Lutaml::Model::Type::Integer", validations: { min: 0 } },
            base64Binary: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A([A-Za-z0-9+\/]+={0,2}|\s)*\z/ } },
            unsignedInt: { class_name: "Lutaml::Model::Type::Integer", validations: { min: 0, max: 4294967295 } },
            hexBinary: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /([0-9a-fA-F]{2})*/ } },
            dateTime: { skippable: true, class_name: "Lutaml::Model::Type::DateTime" },
            boolean: { skippable: true, class_name: "Lutaml::Model::Type::Boolean" },
            integer: { skippable: true, class_name: "Lutaml::Model::Type::Integer" },
            string: { skippable: true, class_name: "Lutaml::Model::Type::String" },
            token: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A[^\t\n\f\r ]+(?: [^\t\n\f\r ]+)*\z/ } },
            long: { class_name: "Lutaml::Model::Type::Decimal" },
            int: { skippable: true, class_name: "Lutaml::Model::Type::Integer" }
          }.freeze

          REF_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
          # frozen_string_literal: true

          class <%= klass_name %> < <%= parent_class %>; end

          TEMPLATE

          SUPPORTED_TYPES_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
          # frozen_string_literal: true

          class <%= Utils.camel_case(klass_name.to_s) %> < <%= properties[:class_name].to_s %>
            def self.cast(value)
              value = super(value)
          <%= "    pattern = \#{validations[:pattern]}\n\#{indent}raise Lutaml::Model::InvalidValueError, \\\"The value \\\#{value} does not match the required pattern: \\\#{pattern}\\\" unless value.match?(pattern)\n" if validations.key?(:pattern) -%>
          <%= "    min = \#{validations[:min]}\n\#{indent}raise Lutaml::Model::InvalidValueError, \\\"The value \\\#{value} is less than the set limit: \\\#{min}\\\" if value < min\n" if validations.key?(:min) -%>
          <%= "    max = \#{validations[:max]}\n\#{indent}raise Lutaml::Model::InvalidValueError, \\\"The value \\\#{value} is greater than the set limit: \\\#{max}\\\" if value > max\n" if validations.key?(:max) -%>
              value
            end
          end

          TEMPLATE

          UNION_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
          # frozen_string_literal: true

          class <%= klass_name %> < Lutaml::Model::Type
            def self.cast(value)
              <%= unions.map { |union| "\#{Utils.camel_case(union.base_class.split(':').last)}.cast(value)" }.join(" || ") %>
            end
          end

          TEMPLATE

          MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
          # frozen_string_literal: true

          class <%= klass_name %> < <%= parent_class %>
          <%= "  VALUES = \#{values}.freeze\n\n" if values_exist = values&.any? -%>
          <%= "  LENGTHS = \#{properties[:length]&.map(&:value)}\n\n" if length_exist = properties&.key?(:length) -%>
            def self.cast(value)
              value = super(value)
          <%= "    pattern = \#{properties[:pattern]}\n    raise_pattern_error(value, pattern) unless value.match?(pattern)\n" if pattern_exist = properties.key?(:pattern) -%>
          <%= "    raise_values_error(value) unless VALUES.include?(value)\n" if values_exist -%>
          <%= "    raise_length_error(value) unless LENGTHS.all?(value.length)\n" if properties&.key?(:length) -%>
          <%= "    min_length = \#{properties.min_length}\n    raise_min_length_error(value, min_length) unless value.length >= min_length\n" if min_length_exist = properties&.key_exist?(:min_length) -%>
          <%= "    max_length = \\\#{properties.max_length}\n    raise_max_length_error(value, max_length) unless value.length <= max_length\n" if max_length_exist = properties&.key_exist?(:max_length) -%>
          <%= "    min_bound = \#{properties[:min_inclusive] || properties[:min_exclusive]}\n    raise_min_bound_error(value, min_bound) unless value \#{properties.key?(:min_inclusive) ? '=>' : '>'} min_bound \n" if min_bound_exist = (properties&.key_exist?(:min_inclusive) || properties&.key_exist?(:min_exclusive)) -%>
          <%= "    max_bound = \#{properties[:max_inclusive] || properties[:max_exclusive]}\n    raise_max_bound_error(value, max_bound) unless value \#{properties.key?(:max_inclusive) ? '=<' : '<'} max_bound \n" if max_bound_exist = (properties&.key_exist?(:max_inclusive) || properties&.key_exist?(:max_exclusive)) -%>
              <%= "value" %>
            end
          <%= "\n  private\n" if pattern_exist || values_exist || length_exist || min_length_exist || max_length_exist || min_bound_exist || max_bound_exist -%>
          <%= "\n  def raise_pattern_error(value, pattern)\n    raise Lutaml::Model::InvalidValueError, \\\"The value \\\#{value} does not match the required pattern: \\\#{pattern}\\\"\n  end\n" if pattern_exist -%>
          <%= "\n  def raise_values_error(input_value)\n    raise Lutaml::Model::InvalidValueError, \\\"Invalid value: \\\\\\\"\\\#{input_value}\\\\\\\". Allowed values are: \\\#{VALUES.join(', ')}\\\"\n  end\n" if values_exist -%>
          <%= "\n  def raise_length_error(input_value)\n    raise Lutaml::Model::InvalidValueError, \\\"The provided value \\\\\\\"\\\#{input_value}\\\\\\\" should match the specified lengths: \\\#{LENGTHS.join(',')}\\\"\n  end\n" if length_exist -%>
          <%= "\n  def raise_min_length_error(input_value, min_length)\n    raise Lutaml::Model::InvalidValueError, \\\"The provided value \\\\\\\"\\\#{input_value}\\\\\\\" has fewer characters than the minimum allowed \\\#{min_length}\\\"\n  end\n" if min_length_exist -%>
          <%= "\n  def raise_max_length_error(input_value, max_length)\n    raise Lutaml::Model::InvalidValueError, \\\"The provided value \\\\\\\"\\\#{input_value}\\\\\\\" exceeds the maximum allowed length of \\\#{max_length}\\\"\n  end\n" if max_length_exist -%>
          <%= "\n  def raise_min_bound_error(input_value, min_bound)\n    raise Lutaml::Model::InvalidValueError, \\\"The provided value \\\\\\\"\\\#{input_value}\\\\\\\" is less than the minimum allowed value of \\\#{min_bound}\\\"\n  end\n" if min_bound_exist -%>
          <%= "\n  def raise_max_bound_error(input_value, max_bound)\n    raise Lutaml::Model::InvalidValueError, \\\"The provided value \\\\\\\"\\\#{input_value}\\\\\\\" exceeds the maximum allowed value of \\\#{max_bound}\\\"\n  end\n" if max_bound_exist -%>
          end

          TEMPLATE

          def create_simple_types(simple_types)
            setup_supported_types
            simple_types.each do |name, properties|
              klass_name = Utils.camel_case(name)


              result = if @simple_types.key?(properties[:base_class])
                parent_class = properties.base_class
                REF_TEMPLATE.result(binding)
              elsif properties&.key_exist?(:union)
                unions = properties.union
                UNION_TEMPLATE.result(binding)
              else
                base_class = properties.base_class.split(":")&.last
                parent_class = if SUPPORTED_DATA_TYPES[base_class.to_sym]&.key?(:class_name)
                  SUPPORTED_DATA_TYPES.dig(base_class.to_sym, :class_name)
                else
                  Utils.camel_case(base_class.to_s)
                end
                values = properties[:values] if properties.key_exist?(:values)
                MODEL_TEMPLATE.result(binding)
              end
              @simple_types[name] = result
            end
            @simple_types
          end

          def setup_supported_types
            @simple_types ||= MappingHash.new
            indent = "    "
            SUPPORTED_DATA_TYPES.each do |klass_name, properties|
              validations = properties[:validations] || {}
              next if properties[:skippable]

              @simple_types[klass_name] = SUPPORTED_TYPES_TEMPLATE.result(binding)
            end
          end
        end
      end
    end
  end
end
