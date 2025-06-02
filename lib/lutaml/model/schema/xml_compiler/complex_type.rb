module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class ComplexType
          attr_accessor :id,
                        :name,
                        :mixed,
                        :instances,
                        :simple_content

          INDENT = "  "

          SIMPLE_CONTENT_ATTRIBUTE_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>attribute :<%= name %>, :<%= simple_content.base_class %>
            <%= simple_content.to_attributes(indent) -%>
          TEMPLATE

          SIMPLE_CONTENT_MAPPING = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>map_content to: :<%= name %>
          TEMPLATE

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true
            <%=  "\n" + required_files.uniq.join("\n") -%>

            class <%= Utils.camel_case(name) %> < Lutaml::Model::Serializable
            <%= instances.map { |instance| instance.to_attributes(indent) }.compact.join + "\n" -%>
            <%= simple_content? ? SIMPLE_CONTENT_ATTRIBUTE_TEMPLATE.result(binding) : nil -%>
            <%= indent %>xml do
            <%= indent + INDENT %>root "<%= name %>"<%= root_options %>
            <%= simple_content? ? SIMPLE_CONTENT_MAPPING.result(binding) : nil -%>
            <%= instances.map { |instance| instance.to_xml_mapping(indent + INDENT) }.compact.join -%>
            <%= indent %>end
            end

            register = Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
            register.register_model(<%= Utils.camel_case(name) %>, id: :<%= Utils.snake_case(name) %>)
          TEMPLATE

          def initialize
            @instances = []
          end

          def <<(instance)
            @instances << instance
          end

          def simple_content?
            @simple_content
          end

          def to_class(indent = INDENT)
            TEMPLATE.result(binding)
          end

          private

          def required_files
            @instances.map(&:required_files).flatten.compact.uniq
          end

          def root_options
            return "" unless mixed

            ", mixed: true"
          end
        end
      end
    end
  end
end
