# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class SimpleType
          attr_accessor :class_name, :base_class, :instance

          DEFAULT_CLASSES = %w[int integer string boolean].freeze

          SUPPORTED_DATA_TYPES = {
            nonNegativeInteger: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\+?[0-9]+/ } },
            positiveInteger: { class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0 } },
            base64Binary: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A([A-Za-z0-9+\/]+={0,2}|\s)*\z/ } },
            unsignedLong: { class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0, max_inclusive: 18446744073709551615 } },
            unsignedInt: { class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0, max_inclusive: 4294967295 } },
            hexBinary: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /([0-9a-fA-F]{2})*/ } },
            dateTime: { skippable: true, class_name: "Lutaml::Model::Type::DateTime" },
            boolean: { skippable: true, class_name: "Lutaml::Model::Type::Boolean" },
            integer: { skippable: true, class_name: "Lutaml::Model::Type::Integer" },
            decimal: { skippable: true, class_name: "Lutaml::Model::Type::Decimal" },
            string: { skippable: true, class_name: "Lutaml::Model::Type::String" },
            anyURI: { class_name: "Lutaml::Model::Type::String", validations: { pattern: "\\A\#{URI::DEFAULT_PARSER.make_regexp(%w[http https ftp])}\\z" } },
            token: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A[^\t\n\f\r ]+(?: [^\t\n\f\r ]+)*\z/ } },
            long: { class_name: "Lutaml::Model::Type::Decimal" },
            int: { skippable: true, class_name: "Lutaml::Model::Type::Integer" },
            id: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
          }.freeze

          INDENT = "  "

          INSTANCE_MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true
            require "lutaml/model"
            <%= "require_relative '\#{Utils.snake_case(parent_class)}'\n" if require_parent? -%>
            <%= required_files -%>

            class <%= klass_name %> < <%= parent_class %>
              def self.cast(value)
                return nil if value.nil?

            <%= instance&.to_method_body(INDENT + INDENT) -%>
                value = super(value)
                value
              end
            end

            register = Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
            register.register_model(<%= klass_name %>, id: :<%= Utils.snake_case(klass_name) %>)
          TEMPLATE

          def initialize(name)
            raise "SimpleType name is required!" if Utils.blank?(name)

            @class_name = name
          end

          def to_class
            INSTANCE_MODEL_TEMPLATE.result(binding)
          end

          def klass_name
            Utils.camel_case(class_name)
          end

          def require_parent?
            !SUPPORTED_DATA_TYPES[base_class&.to_sym]&.key?(:class_name)
          end

          def big_decimal_class?
            base_class.to_s == "decimal"
          end

          def parent_class
            if SUPPORTED_DATA_TYPES[base_class.to_sym]&.key?(:class_name)
              SUPPORTED_DATA_TYPES.dig(base_class.to_sym, :class_name)
            else
              Utils.camel_case(base_class.to_s)
            end
          end

          def required_files
            instance&.required_files
          end

          class << self
            def setup_supported_types
              SUPPORTED_DATA_TYPES.map.with_object({}) do |(name, simple_type), hash|
                next if simple_type[:skippable]

                self.new(name.to_s).tap do |instance|
                  instance.base_class = Utils.base_class_snake_case(simple_type[:class_name])
                  instance.instance = setup_restriction(instance.base_class, simple_type[:validations]) if simple_type[:validations]
                  hash[name.to_s] = instance
                end
              end.compact
            end

            def setup_restriction(base_class, validations)
              Restriction.new.tap do |restriction|
                restriction.base_class = base_class
                restriction.min_inclusive = validations[:min_inclusive]
                restriction.max_inclusive = validations[:max_inclusive]
                restriction.pattern = validations[:pattern]
              end
            end
          end
        end
      end
    end
  end
end
