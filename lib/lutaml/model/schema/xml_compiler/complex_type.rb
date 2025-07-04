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
            <%= @indent %>attribute :content, :<%= simple_content? ? Utils.snake_case(simple_content.base_class.split(":").last) : "string" %>
            <%= simple_content.to_attributes(@indent) if simple_content? -%>
          TEMPLATE

          SIMPLE_CONTENT_MAPPING = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= extended_indent %>map_content to: :content
          TEMPLATE

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true

            <%= base_class_require -%>

            <%= required_files.uniq.join("\n") + "\n" -%>
            class <%= Utils.camel_case(name) %> < <%= base_class_name %>
            <%= instances.map { |instance| instance.to_attributes(@indent) }.compact.join + "\n" -%>
            <%= simple_content_attribute -%>
            <%= @indent %>xml do
            <%= extended_indent %>root "<%= name %>"<%= root_options %>
            <%= namespace_and_prefix %>
            <%= simple_content_value -%>
            <%= instances.map { |instance| instance.to_xml_mapping(extended_indent) }.compact.join -%>
            <%= simple_content.to_xml_mapping(extended_indent) if simple_content? -%>
            <%= @indent %>end
            end

            register = Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
            register.register_model(<%= Utils.camel_case(name) %>, id: :<%= Utils.snake_case(name) %>)
          TEMPLATE

          def initialize(base_class: "Lutaml::Model::Serializable")
            @base_class = base_class
            @instances = []
          end

          def <<(instance)
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
            files = []
            files.concat(@instances.map(&:required_files).flatten.compact.uniq)
            files.concat(simple_content.required_files) if simple_content?
            files
          end

          private

          def setup_options(options)
            @namespace, @prefix = options.values_at(:namespace, :prefix)
            @indent = " " * options&.fetch(:indent, 2)
          end

          def simple_content_attribute
            SIMPLE_CONTENT_ATTRIBUTE_TEMPLATE.result(binding) if simple_content? || mixed
          end

          def root_options
            return "" unless mixed

            ", mixed: true"
          end

          def simple_content_value
            SIMPLE_CONTENT_MAPPING.result(binding) if simple_content? || mixed
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
              Utils.camel_case(base_class.split(":").last)
            end
          end

          def base_class_require
            case base_class
            when SERIALIZABLE_BASE_CLASS
              "require \"lutaml/model\""
            else
              "require_relative \"#{Utils.snake_case(base_class.split(':').last)}\""
            end
          end
        end
      end
    end
  end
end
