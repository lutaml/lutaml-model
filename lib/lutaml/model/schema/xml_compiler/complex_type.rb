module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class ComplexType
          attr_accessor :id,
                        :name,
                        :mixed,
                        :instances,
                        :base_class,
                        :simple_content

          SERIALIZABLE_BASE_CLASS = "Lutaml::Model::Serializable".freeze

          SIMPLE_CONTENT_ATTRIBUTE_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= @indent %>attribute :content, :<%= simple_content_type %>
            <%= simple_content.to_attributes(@indent) if simple_content? -%>
          TEMPLATE

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true

            <%= required_files.uniq.join("\n") + "\n" -%>
            class <%= Utils.camel_case(name) %> < <%= base_class_name %>
            <%= instances.flat_map { |instance| instance.to_attributes(@indent) }.join + "\n" -%>
            <%= simple_content_attribute -%>
            <%= @indent %>xml do
            <%= extended_indent %>root "<%= name %>"<%= root_options %>
            <%= namespace_and_prefix %>
            <%= "\#{extended_indent}map_content to: :content" if simple_content? || mixed %>
            <%= instances.flat_map { |instance| instance.to_xml_mapping(extended_indent) }.join -%>
            <%= simple_content.to_xml_mapping(extended_indent) if simple_content? -%>
            <%= @indent %>end

              def self.register
                Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
              end

              def self.register_class_with_id
                register.register_model(<%= Utils.camel_case(name) %>, id: :<%= Utils.snake_case(name) %>)
              end
            end

            <%= Utils.camel_case(name) %>.register_class_with_id
          TEMPLATE

          def initialize(base_class: SERIALIZABLE_BASE_CLASS)
            @base_class = base_class
            @instances = []
          end

          def <<(instance)
            return if instance.nil?

            @instances << instance
          end

          def simple_content?
            Utils.present?(@simple_content)
          end

          def to_class(options: {})
            setup_options(options)
            TEMPLATE.result(binding)
          end

          def required_files
            files = [base_class_require]
            files.concat(@instances.map(&:required_files).flatten.compact.uniq)
            files.concat(simple_content.required_files) if simple_content?
            files
          end

          private

          def setup_options(options)
            @namespace, @prefix = options.values_at(:namespace, :prefix)
            @indent = " " * options&.fetch(:indent, 2)
          end

          def simple_content_type
            return "string" unless simple_content?

            Utils.snake_case(last_of_split(simple_content.base_class))
          end

          def simple_content_attribute
            SIMPLE_CONTENT_ATTRIBUTE_TEMPLATE.result(binding) if simple_content? || mixed
          end

          def root_options
            return "" unless mixed

            ", mixed: true"
          end

          def namespace_and_prefix
            return "" if Utils.blank?(@namespace) && Utils.blank?(@prefix)

            [namespace_option, @prefix&.inspect].compact.join(", ")
          end

          def extended_indent
            @indent * 2
          end

          def namespace_option
            "#{extended_indent}namespace #{@namespace.inspect}"
          end

          def base_class_name
            case base_class
            when SERIALIZABLE_BASE_CLASS
              SERIALIZABLE_BASE_CLASS
            else
              Utils.camel_case(last_of_split(base_class))
            end
          end

          def base_class_require
            case base_class
            when SERIALIZABLE_BASE_CLASS
              "require \"lutaml/model\""
            else
              "require_relative \"#{Utils.snake_case(last_of_split(base_class))}\""
            end
          end

          def last_of_split(field)
            field&.split(":")&.last
          end
        end
      end
    end
  end
end
