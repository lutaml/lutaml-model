# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class SimpleType
          attr_accessor :class_name, :base_class, :instance, :unions

          LUTAML_VALUE_CLASS_NAME = "Lutaml::Model::Type::Value"

          SUPPORTED_DATA_TYPES = {
            nonNegativeInteger: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\+?[0-9]+/ } },
            normalizedString: { class_name: "Lutaml::Model::Type::String", validations: { transform: "value.gsub(/[\\r\\n\\t]/, ' ')" } },
            positiveInteger: { class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0 } },
            unsignedShort: { class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0, max_inclusive: 65535 } },
            base64Binary: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A([A-Za-z0-9+\/]+={0,2}|\s)*\z/ } },
            unsignedLong: { class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0, max_inclusive: 18446744073709551615 } },
            unsignedByte: { class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0, max_inclusive: 255 } },
            unsignedInt: { class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0, max_inclusive: 4294967295 } },
            hexBinary: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /([0-9a-fA-F]{2})*/ } },
            language: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*\z/ } },
            dateTime: { skippable: true, class_name: "Lutaml::Model::Type::DateTime" },
            boolean: { skippable: true, class_name: "Lutaml::Model::Type::Boolean" },
            integer: { skippable: true, class_name: "Lutaml::Model::Type::Integer" },
            decimal: { skippable: true, class_name: "Lutaml::Model::Type::Decimal" },
            string: { skippable: true, class_name: "Lutaml::Model::Type::String" },
            double: { skippable: true, class_name: "Lutaml::Model::Type::Float" },
            NCName: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
            anyURI: { class_name: "Lutaml::Model::Type::String", validations: { pattern: "\\A\#{URI::DEFAULT_PARSER.make_regexp(%w[http https ftp])}\\z" } },
            token: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A[^\t\n\f\r ]+(?: [^\t\n\f\r ]+)*\z/ } },
            byte: { class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: -128, max_inclusive: 127 } },
            long: { class_name: "Lutaml::Model::Type::Decimal" },
            int: { skippable: true, class_name: "Lutaml::Model::Type::Integer" },
            id: { class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
          }.freeze

          INSTANCE_MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true
            require "lutaml/model"

            <%= "require_relative \\"\#{Utils.snake_case(parent_class)}\\"\n" if require_parent? -%>
            <%= "\#{required_files}\n" -%>
            class <%= klass_name %><%= " < \#{parent_class}" if parent_class %>
              def self.cast(value, options = {})
                return if value.nil?

            <%= instance&.to_method_body(@indent * 2) -%>
                value = super(value, options)
                value
              end
            end

            register = Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
            register.register_model(<%= klass_name %>, id: :<%= Utils.snake_case(class_name) %>)
          TEMPLATE

          UNION_MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true
            require "lutaml/model"
            <%= union_required_files %>

            class <%= klass_name %> < <%= LUTAML_VALUE_CLASS_NAME %>
              def self.cast(value, options = {})
                return if value.nil?

            <%= union_class_method_body %>
              end

              def self.register
                @register ||= Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
              end

              def self.register_class_with_id
                register.register_model(<%= klass_name %>, id: :<%= Utils.snake_case(class_name) %>)
              end
            end

            <%= klass_name %>.register_class_with_id
          TEMPLATE

          def initialize(name, unions = [])
            raise "SimpleType name is required!" if Utils.blank?(name)

            @class_name = name
            @unions = unions
          end

          def to_class(options: {})
            setup_options(options)
            template = unions&.any? ? UNION_MODEL_TEMPLATE : INSTANCE_MODEL_TEMPLATE
            template.result(binding)
          end

          def required_files
            instance&.required_files
          end

          private

          def setup_options(options)
            @indent = " " * options&.fetch(:indent, 2)
          end

          def klass_name
            @klass_name ||= Utils.camel_case(class_name)
          end

          def require_parent?
            !SUPPORTED_DATA_TYPES[base_class&.to_sym]&.key?(:class_name)
          end

          def parent_class
            types = SUPPORTED_DATA_TYPES
            if types.key?(base_class&.to_sym) && !types.dig(base_class&.to_sym, :skippable)
              Utils.camel_case(base_class)
            elsif types.dig(base_class&.to_sym, :class_name) && types.dig(base_class&.to_sym, :skippable)
              types.dig(base_class&.to_sym, :class_name)
            elsif base_class
              Utils.camel_case(base_class.to_s)
            else
              LUTAML_VALUE_CLASS_NAME
            end
          end

          def union_class_method_body
            unions.map do |union|
              "#{@indent * 2}register.get_class(:#{Utils.snake_case(union.split(':').last)}).cast(value, options)"
            end.join(" ||\n  ")
          end

          def union_required_files
            unions.filter_map do |union|
              next if SUPPORTED_DATA_TYPES.dig(union.split(":").last.to_sym, :skippable)

              "require_relative \"#{Utils.snake_case(union.split(':').last)}\""
            end.join("\n")
          end

          class << self
            def setup_supported_types
              SUPPORTED_DATA_TYPES.filter_map.with_object({}) do |(name, simple_type), hash|
                next if simple_type[:skippable]

                new(name.to_s).tap do |instance|
                  instance.base_class = Utils.base_class_snake_case(simple_type[:class_name])
                  instance.instance = setup_restriction(instance.base_class, simple_type[:validations]) if simple_type[:validations]
                  hash[name.to_s] = instance
                end
              end
            end

            def setup_restriction(base_class, validations)
              Restriction.new.tap do |restriction|
                restriction.base_class = base_class
                restriction.min_inclusive = validations[:min_inclusive]
                restriction.max_inclusive = validations[:max_inclusive]
                restriction.pattern = validations[:pattern]
                restriction.transform = validations[:transform]
              end
            end
          end
        end
      end
    end
  end
end
