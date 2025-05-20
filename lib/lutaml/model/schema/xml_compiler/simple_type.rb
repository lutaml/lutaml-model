# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class SimpleType
          attr_accessor :class_name, :simple_types, :restriction, :union

          DEFAULT_CLASSES = %w[int integer string boolean].freeze

          SUPPORTED_DATA_TYPES = {
            nonNegativeInteger: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\+?[0-9]+/ } },
            positiveInteger: { class_name: "Lutaml::Model::Type::Integer", validations: { min: 0 } },
            base64Binary: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A([A-Za-z0-9+\/]+={0,2}|\s)*\z/ } },
            unsignedLong: { class_name: "Lutaml::Model::Type::Integer", validations: { min: 0, max: 18446744073709551615 } },
            unsignedInt: { class_name: "Lutaml::Model::Type::Integer", validations: { min: 0, max: 4294967295 } },
            hexBinary: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /([0-9a-fA-F]{2})*/ } },
            dateTime: { skippable: true, class_name: "Lutaml::Model::Type::DateTime" },
            boolean: { skippable: true, class_name: "Lutaml::Model::Type::Boolean" },
            integer: { skippable: true, class_name: "Lutaml::Model::Type::Integer" },
            string: { skippable: true, class_name: "Lutaml::Model::Type::String" },
            token: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A[^\t\n\f\r ]+(?: [^\t\n\f\r ]+)*\z/ } },
            long: { class_name: "Lutaml::Model::Type::Decimal" },
            int: { skippable: true, class_name: "Lutaml::Model::Type::Integer" },
            id: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
          }.freeze

          REF_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true

            require "lutaml/model"
            <%= "require_relative \#{Utils.snake_case(parent_class).inspect}\n" if require_parent -%>

            class <%= klass_name %> < <%= Utils.camel_case(parent_class) %>; end

            register = Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
            register.register_model(<%= klass_name %>, id: :<%= Utils.snake_case(klass_name) %>)
          TEMPLATE

          SUPPORTED_TYPES_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true

            require "lutaml/model"

            class <%= Utils.camel_case(klass_name.to_s) %> < <%= properties[:class_name].to_s %>
              def self.cast(value)
                return nil if value.nil?

                value = super(value)
            <%=
              if pattern_exist = validations.key?(:pattern)
                "    pattern = %r{\#{validations[:pattern]}}\n\#{indent}raise Lutaml::Model::Type::InvalidValueError, \\"The value \\\#{value} does not match the required pattern: \\\#{pattern}\\" unless value.match?(pattern)\n"
              end
            -%>
            <%=
              if min_exist = validations.key?(:min)
                "    min = \#{validations[:min]}\n\#{indent}raise Lutaml::Model::Type::InvalidValueError, \\"The value \\\#{value} is less than the set limit: \\\#{min}\\" if value < min\n"
              end
            -%>
            <%=
              if max_exist = validations.key?(:max)
                "    max = \#{validations[:max]}\n\#{indent}raise Lutaml::Model::Type::InvalidValueError, \\"The value \\\#{value} is greater than the set limit: \\\#{max}\\" if value > max\n"
              end
            -%>
                value
              end
            end

            register = Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
            register.register_model(<%= Utils.camel_case(klass_name.to_s) %>, id: :<%= Utils.snake_case(klass_name) %>)
          TEMPLATE

          UNION_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true

            require "lutaml/model"
            <%=
              resolve_required_files(unions)&.map do |file|
                next if file.nil? || file.empty?

                "require_relative \\\"\#{file}\\\""
              end.compact.join("\n") + "\n"
            -%>

            class <%= klass_name %> < Lutaml::Model::Type::Value
              def self.cast(value)
                return nil if value.nil?

                <%= unions.map do |union|
                  base_class = union.base_class.split(':').last
                  if DEFAULT_CLASSES.include?(base_class)
                    "\#{SUPPORTED_DATA_TYPES.dig(base_class.to_sym, :class_name)}.cast(value)"
                  else
                    "\#{Utils.camel_case(base_class)}.cast(value)"
                  end
                end.join(" || ") %>
              end
            end

            register = Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
            register.register_model(<%= klass_name %>, id: :<%= Utils.snake_case(klass_name) %>)
          TEMPLATE

          MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true
            require "lutaml/model"
            <%= "require_relative '\#{Utils.snake_case(parent_class)}'\n" if require_parent -%>

            class <%= klass_name %> < <%= parent_class %>
            <%= "  VALUES = \#{values}.freeze\n\n" if values_exist = values&.any? -%>
            <%= "  LENGTHS = \#{properties[:length]&.map(&:value)}\n\n" if length_exist = properties&.key?(:length) -%>
              def self.cast(value)
                return nil if value.nil?

                value = super(value)
            <%= "    raise_values_error(value) unless VALUES.include?(value)\n" if values_exist -%>
            <%= "    raise_length_error(value) unless LENGTHS.all?(value.length)\n" if length_exist -%>
            <%=
              if pattern_exist = properties.key?(:pattern)
                "    pattern = %r{\#{properties[:pattern]}}\n    raise_pattern_error(value, pattern) unless value.match?(pattern)\n"
              end
            -%>
            <%=
              if min_length_exist = properties&.key_exist?(:min_length)
                "    min_length = \#{properties.min_length}\n    raise_min_length_error(value, min_length) unless value.length >= min_length\n"
              end
            -%>
            <%=
              if max_length_exist = properties&.key_exist?(:max_length)
                "    max_length = \#{properties.max_length}\n    raise_max_length_error(value, max_length) unless value.length <= max_length\n"
              end
            -%>
            <%=
              if min_bound_exist = (properties&.key_exist?(:min_inclusive) || properties&.key_exist?(:min_exclusive))
                "    min_bound = \#{properties[:min_inclusive] || properties[:min_exclusive]}\n    raise_min_bound_error(value, min_bound) unless value >\#{'=' if properties.key?(:min_inclusive)} min_bound \n"
              end
            -%>
            <%=
              if max_bound_exist = (properties&.key_exist?(:max_inclusive) || properties&.key_exist?(:max_exclusive))
                "    max_bound = \#{properties[:max_inclusive] || properties[:max_exclusive]}\n    raise_max_bound_error(value, max_bound) unless value <\#{'=' if properties.key?(:max_inclusive)} max_bound \n"
              end
            -%>
                <%= "value" %>
              end
            <%= "\n  private\n" if pattern_exist || values_exist || length_exist || min_length_exist || max_length_exist || min_bound_exist || max_bound_exist -%>
            <%=
              if pattern_exist
                "\n  def self.raise_pattern_error(value, pattern)\n    raise Lutaml::Model::Type::InvalidValueError, \\"The value \\\#{value} does not match the required pattern: \\\#{pattern}\\"\n  end\n"
              end
            -%>
            <%=
              if values_exist
                "\n  def self.raise_values_error(input_value)\n    raise Lutaml::Model::InvalidValueError.new(self, input_value, VALUES)\n  end\n"
              end
            -%>
            <%=
              if length_exist
                "\n  def self.raise_length_error(input_value)\n    raise Lutaml::Model::Type::InvalidValueError, \\"The provided value \\\\\\"\\\#{input_value}\\\\\\" should match the specified lengths: \\\#{LENGTHS.join(',')}\\"\n  end\n"
              end
            -%>
            <%=
              if min_length_exist
                "\n  def self.raise_min_length_error(input_value, min_length)\n    raise Lutaml::Model::Type::InvalidValueError, \\"The provided value \\\\\\"\\\#{input_value}\\\\\\" has fewer characters than the minimum allowed \\\#{min_length}\\"\n  end\n"
              end
            -%>
            <%=
              if max_length_exist
                "\n  def self.raise_max_length_error(input_value, max_length)\n    raise Lutaml::Model::Type::InvalidValueError, \\"The provided value \\\\\\"\\\#{input_value}\\\\\\" exceeds the maximum allowed length of \\\#{max_length}\\"\n  end\n"
              end
            -%>
            <%=
              if min_bound_exist
                "\n  def self.raise_min_bound_error(input_value, min_bound)\n    raise Lutaml::Model::Type::InvalidValueError, \\"The provided value \\\\\\"\\\#{input_value}\\\\\\" is less than the minimum allowed value of \\\#{min_bound}\\"\n  end\n"
              end
            -%>
            <%=
              if max_bound_exist
                "\n  def self.raise_max_bound_error(input_value, max_bound)\n    raise Lutaml::Model::Type::InvalidValueError, \\"The provided value \\\\\\"\\\#{input_value}\\\\\\" exceeds the maximum allowed value of \\\#{max_bound}\\"\n  end\n"
              end
            -%>
            end

            register = Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
            register.register_model(<%= klass_name %>, id: :<%= Utils.snake_case(klass_name) %>)
          TEMPLATE

          def initialize(name)
            raise "SimpleType name is required!" if Utils.blank?(name)

            @class_name = name
          end

          def create_simple_types(simple_types)
            setup_supported_types
            simple_types.each do |name, properties|
              klass_name = Utils.camel_case(name)
              @simple_types[name] = if @simple_types.key?(properties[:base_class]) && properties.one?
                                      ref_template(properties, klass_name)
                                    elsif properties&.key_exist?(:union)
                                      union_template(properties, klass_name)
                                    else
                                      model_template(properties, klass_name)
                                    end
            end
            @simple_types
          end

          # klass_name is used in template using `binding`
          def model_template(properties, klass_name)
            base_class = properties.base_class.split(":")&.last
            parent_class, require_parent = extract_parent_class(base_class)
            values = properties[:values] if properties.key_exist?(:values)
            MODEL_TEMPLATE.result(binding)
          end

          def extract_parent_class(base_class)
            klass = if SUPPORTED_DATA_TYPES[base_class.to_sym]&.key?(:class_name)
                      parent = false
                      SUPPORTED_DATA_TYPES.dig(base_class.to_sym, :class_name)
                    else
                      parent = true
                      Utils.camel_case(base_class.to_s)
                    end
            [klass, parent]
          end

          # klass_name is used in template using `binding`
          def union_template(properties, klass_name)
            unions = properties.union
            UNION_TEMPLATE.result(binding)
          end

          # klass_name is used in template using `binding`
          def ref_template(properties, klass_name)
            parent_class = properties.base_class
            require_parent = true unless properties[:base_class].include?("Lutaml::Model::")
            REF_TEMPLATE.result(binding)
          end

          def setup_supported_types
            @simple_types = MappingHash.new
            indent = "    "
            SUPPORTED_DATA_TYPES.each do |klass_name, properties|
              validations = properties[:validations] || {}
              next if properties[:skippable]

              @simple_types[klass_name] = SUPPORTED_TYPES_TEMPLATE.result(binding)
            end
          end

          def resolve_required_files(unions)
            unions.map do |union|
              next if DEFAULT_CLASSES.include?(union.base_class.split(":").last)

              Utils.snake_case(union.base_class.split(":").last)
            end
          end
        end
      end
    end
  end
end
