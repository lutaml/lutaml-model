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
            <%= indent %>attribute :<%= simple_content? ? name : "content" %>, :<%= simple_content? ? simple_content.base_class : "string" %>
            <%= simple_content.to_attributes(indent) if simple_content? -%>
          TEMPLATE

          SIMPLE_CONTENT_MAPPING = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>map_content to: :<%= name %>
          TEMPLATE

          MIXED_CONTENT_MAPPING = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>map_content to: :content
          TEMPLATE

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true
            <%=  "\n" + required_files.uniq.join("\n") -%>

            class <%= Utils.camel_case(name) %> < Lutaml::Model::Serializable
            <%= instances.map { |instance| instance.to_attributes(indent) }.compact.join + "\n" -%>
            <%= simple_content_attribute(indent) -%>
            <%= indent %>xml do
            <%= namespace_and_prefix(indent) -%>
            <%= indent + INDENT %>root "<%= name %>"<%= root_options %>
            <%= simple_content_value(indent) -%>
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

          def to_class(indent = INDENT, options: {})
            setup_options(options)
            TEMPLATE.result(binding)
          end

          private

          def setup_options(options)
            @namespace = options[:namespace]
            @prefix = options[:prefix]
          end

          def required_files
            @instances.map(&:required_files).flatten.compact.uniq
          end

          def root_options
            return "" unless mixed

            ", mixed: true"
          end

          def simple_content_attribute(indent)
            if simple_content? || mixed
              SIMPLE_CONTENT_ATTRIBUTE_TEMPLATE.result(binding)
            end
          end

          def simple_content_value(indent)
            if simple_content?
              SIMPLE_CONTENT_MAPPING.result(binding)
            elsif mixed
              MIXED_CONTENT_MAPPING.result(binding)
            end
          end

          def namespace_and_prefix(indent)
            return "" if Utils.blank?(@namespace) && Utils.blank?(@prefix)

            [indent + INDENT, namespace_option, prefix_option].compact.join
          end

          def namespace_option
            "namespace '#{@namespace}'" if @namespace
          end

          def prefix_option
            ", '#{@prefix}'" if @prefix
          end
        end
      end
    end
  end
end
