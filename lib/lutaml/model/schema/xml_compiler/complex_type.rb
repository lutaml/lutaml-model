module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class ComplexType
          attr_accessor :id,
                        :name,
                        :mixed,
                        :instances

          INDENT = "  "

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true
            <%= required_files -%>

            class <%= Utils.camel_case(name) %> < Lutaml::Model::Serializable
            <%= instances.map { |instance| instance.to_attributes(indent) }.compact.join + "\n" -%>
            <%= indent %>xml do
            <%= indent + INDENT %>root "<%= name %>"<%= root_options %>

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

          def to_class(indent = INDENT)
            TEMPLATE.result(binding)
          end

          private

          # TODO: IN PROGRESS
          def required_files
            return "" unless mixed

            files = @instances.map(&:required_files)
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
