# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class SimpleType
          attr_accessor :class_name, :base_class, :instance, :unions

          LUTAML_VALUE_CLASS_NAME = "Lutaml::Model::Type::Value"

          SUPPORTED_DATA_TYPES = {
            nonNegativeInteger: { skippable: false,
                                  class_name: "Lutaml::Model::Type::String", validations: { pattern: /\+?[0-9]+/ } },
            normalizedString: { skippable: false,
                                class_name: "Lutaml::Model::Type::String", validations: { transform: "value.gsub(/[\\r\\n\\t]/, ' ')" } },
            positiveInteger: { skippable: false,
                               class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0 } },
            unsignedShort: { skippable: false,
                             class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0, max_inclusive: 65535 } },
            base64Binary: { skippable: false,
                            class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A([A-Za-z0-9+\/]+={0,2}|\s)*\z/ } },
            unsignedLong: { skippable: false,
                            class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0, max_inclusive: 18446744073709551615 } },
            unsignedByte: { skippable: false,
                            class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0, max_inclusive: 255 } },
            unsignedInt: { skippable: false,
                           class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: 0, max_inclusive: 4294967295 } },
            hexBinary: { skippable: false,
                         class_name: "Lutaml::Model::Type::String", validations: { pattern: /([0-9a-fA-F]{2})*/ } },
            language: { skippable: false,
                        class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*\z/ } },
            dateTime: { skippable: true,
                        class_name: "Lutaml::Model::Type::DateTime" },
            boolean: { skippable: true,
                       class_name: "Lutaml::Model::Type::Boolean" },
            integer: { skippable: true,
                       class_name: "Lutaml::Model::Type::Integer" },
            decimal: { skippable: true,
                       class_name: "Lutaml::Model::Type::Decimal" },
            string: { skippable: true,
                      class_name: "Lutaml::Model::Type::String" },
            double: { skippable: true,
                      class_name: "Lutaml::Model::Type::Float" },
            NCName: { skippable: false,
                      class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
            anyURI: { skippable: false,
                      class_name: "Lutaml::Model::Type::String", validations: { pattern: "\\A\#{URI::DEFAULT_PARSER.make_regexp(%w[http https ftp])}\\z" } },
            token: { skippable: false,
                     class_name: "Lutaml::Model::Type::String", validations: { pattern: /\A[^\t\n\f\r ]+(?: [^\t\n\f\r ]+)*\z/ } },
            byte: { skippable: false,
                    class_name: "Lutaml::Model::Type::Integer", validations: { min_inclusive: -128, max_inclusive: 127 } },
            long: { skippable: false,
                    class_name: "Lutaml::Model::Type::Decimal" },
            int: { skippable: true,
                   class_name: "Lutaml::Model::Type::Integer" },
            id: { skippable: false, class_name: "Lutaml::Model::Type::String",
                  validations: { pattern: /\A[a-zA-Z_][\w.-]*\z/ } },
          }.freeze

          INSTANCE_MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true
            require "lutaml/model"

            <%= "\#{required_files}\n" -%>
            <%= module_opening -%>
            class <%= klass_name %><%= " < \#{parent_class}" if parent_class %>
            <%= @indent %>def self.cast(value, options = {})
            <%= extended_indent %>return if value.nil?

            <%= instance&.to_method_body(extended_indent) %>
                value = super(value, options)
                value
              end
            <%= registration_methods -%>
            end
            <%= module_closing -%>
            <%= registration_execution -%>
          TEMPLATE

          UNION_MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true
            require "lutaml/model"
            <%= union_required_files %>

            <%= module_opening -%>
            class <%= klass_name %> < <%= LUTAML_VALUE_CLASS_NAME %>
            <%= @indent %>def self.cast(value, options = {})
            <%= extended_indent %>return if value.nil?

            <%= union_class_method_body %>
              end
            <%= registration_methods -%>
            end
            <%= module_closing -%>
            <%= registration_execution -%>
          TEMPLATE

          def initialize(name, unions = [])
            @class_name = name
            @unions = unions
            @module_namespace = nil
          end

          def to_class(options: {})
            setup_options(options)
            template = unions&.any? ? UNION_MODEL_TEMPLATE : INSTANCE_MODEL_TEMPLATE
            template.result(binding)
          end

          def required_files
            files = Array(instance&.required_files)
            # Don't add requires for parent classes if using module namespace
            # They're handled via central autoload registry
            if !@module_namespace && require_parent?
              files << "require_relative \"#{Utils.snake_case(parent_class)}\""
            end
            # Filter out require_relative when using autoload, keep external requires
            if @module_namespace
              files = files.select { |f| f.start_with?("require \"") }
            end
            files.join("\n")
          end

          private

          def setup_options(options)
            @indent = " " * options&.fetch(:indent, 2)
            @extended_indent = @indent * 2
            @module_namespace = options[:module_namespace]
            @modules = @module_namespace&.split("::") || []
            @register_id = options[:register_id]
          end

          def module_opening
            return "" if @modules.empty?

            @modules.map.with_index do |mod, i|
              "#{'  ' * i}module #{mod}"
            end.join("\n") + "\n"
          end

          def module_closing
            return "" if @modules.empty?

            @modules.reverse.map.with_index do |_mod, i|
              "#{'  ' * (@modules.size - i - 1)}end"
            end.join("\n")
          end

          def registration_methods
            if @module_namespace
              # Still need register method for union types that call register.get_class
              <<~REGISTRATION

                #{@indent}def self.register
                #{extended_indent}Lutaml::Model::Config.default_register
                #{@indent}end
              REGISTRATION
            else
              <<~REGISTRATION

                #{@indent}def self.register
                #{extended_indent}@register ||= Lutaml::Model::Config.default_register
                #{@indent}end

                #{@indent}def self.register_class_with_id
                #{extended_indent}context = Lutaml::Model::GlobalContext.context(Lutaml::Model::Config.default_register)
                #{extended_indent}context.registry.register(:#{Utils.snake_case(class_name)}, self)
                #{@indent}end
              REGISTRATION
            end
          end

          def registration_execution
            return "" if @module_namespace

            "\n#{klass_name}.register_class_with_id"
          end

          def klass_name
            @klass_name ||= Utils.camel_case(class_name)
          end

          def require_parent?
            return false if Utils.blank?(base_class)

            !!!SUPPORTED_DATA_TYPES[base_class&.to_sym]&.dig(:skippable)
          end

          def parent_class
            type_info = SUPPORTED_DATA_TYPES[base_class&.to_sym]
            return type_info[:class_name] if type_info&.dig(:skippable)
            return Utils.camel_case(base_class.to_s) if !!!type_info&.dig(:skippable) && Utils.present?(base_class)

            LUTAML_VALUE_CLASS_NAME
          end

          def union_class_method_body
            unions.map do |union|
              "#{extended_indent}Lutaml::Model::GlobalContext.resolve_type(:#{down_union_class_name(union)}, @register).cast(value, options)"
            end.join(" ||\n  ")
          end

          def union_required_files
            # Don't add requires for union classes if using module namespace
            # They're handled via central autoload registry
            return "" if @module_namespace

            unions.filter_map do |union|
              next if SUPPORTED_DATA_TYPES.dig(last_of_split(union).to_sym,
                                               :skippable)

              "require_relative \"#{down_union_class_name(union)}\""
            end.join("\n")
          end

          def down_union_class_name(union)
            Utils.snake_case(last_of_split(union))
          end

          def last_of_split(field)
            field&.split(":")&.last
          end

          def extended_indent
            @extended_indent || "    "
          end

          class << self
            def setup_supported_types
              SUPPORTED_DATA_TYPES.reject do |_, simple_type|
                simple_type[:skippable]
              end.each_with_object({}) do |(name, simple_type), hash|
                str_name = name.to_s
                new(str_name).tap do |instance|
                  instance.base_class = Utils.base_class_snake_case(simple_type[:class_name])
                  instance.instance = setup_restriction(instance.base_class,
                                                        simple_type[:validations])
                  hash[str_name] = instance
                end
              end
            end

            def setup_restriction(base_class, validations)
              return unless validations

              Restriction.new.tap do |restriction|
                restriction.base_class = base_class
                restriction.min_inclusive = validations[:min_inclusive]
                restriction.max_inclusive = validations[:max_inclusive]
                restriction.pattern = validations[:pattern]
                restriction.transform = validations[:transform]
              end
            end

            def skippable?(type)
              SUPPORTED_DATA_TYPES.dig(type&.to_sym, :skippable)
            end
          end
        end
      end
    end
  end
end
