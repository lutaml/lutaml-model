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
            <%= extended_indent %>element "<%= name %>"
            <%= extended_indent %><%= mixed_content? %>
            <%= namespace_and_prefix %>
            <%= "\#{extended_indent}map_content to: :content" if simple_content? || mixed %>
            <%= instances.flat_map { |instance| instance.to_xml_mapping(extended_indent) }.join -%>
            <%= simple_content.to_xml_mapping(extended_indent) if simple_content? -%>
            <%= @indent %>end

            <%= @indent %>def self.register
            <%= extended_indent %>Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
            <%= @indent %>end

            <%= @indent %>def self.register_class_with_id
            <%= extended_indent %>register.register_model(self, id: :<%= Utils.snake_case(name) %>)
            <%= @indent %>end
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
            if @namespace_class_name
              # Add require for the namespace class
              files << "require_relative \"#{Utils.snake_case(@namespace_class_name)}\""
            end
            files.concat(@instances.map(&:required_files).flatten.compact.uniq)
            files.concat(simple_content.required_files) if simple_content?
            files
          end

          private

          def setup_options(options)
            namespace_uri = options[:namespace]
            @prefix = options[:prefix]
            @indent = " " * options&.fetch(:indent, 2)

            # Get the namespace class name if namespace URI is provided
            if namespace_uri && XmlCompiler.namespace_classes
              ns_class = XmlCompiler.namespace_classes.values.find { |ns| ns.uri == namespace_uri }
              @namespace_class_name = ns_class&.class_name
            end
          end

          def simple_content_type
            return "string" unless simple_content?

            Utils.snake_case(last_of_split(simple_content.base_class))
          end

          def simple_content_attribute
            SIMPLE_CONTENT_ATTRIBUTE_TEMPLATE.result(binding) if simple_content? || mixed
          end

          def mixed_content?
            mixed ? "mixed_content" : ""
          end

          def namespace_and_prefix
            return "" unless @namespace_class_name

            "#{extended_indent}namespace #{@namespace_class_name}"
          end

          def extended_indent
            @indent * 2
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
