# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Group
          attr_accessor :name, :ref, :instance

          GROUP_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true

            <%=  "\n" + required_files.uniq.join("\n") -%>

            class <%= Utils.camel_case(base_name) %> < Lutaml::Model::Serializable
            <%= definitions_content %>
            <%= xml_mapping_block -%>

            <%= @indent %>def self.register
            <%= extended_indent %>@register ||= Lutaml::Model::GlobalRegister.lookup(Lutaml::Model::Config.default_register)
            <%= @indent %>end

            <%= @indent %>def self.register_class_with_id
            <%= extended_indent %>register.register_model(self, id: :<%= Utils.snake_case(base_name) %>)
            <%= @indent %>end
            end

            <%= Utils.camel_case(base_name) %>.register_class_with_id
          TEMPLATE

          XML_MAPPING_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= @indent %>xml do
            <%= extended_indent %>type_name "<%= base_name %>"
            <%= xml_mapping_content -%>
            <%= @indent %>end
          TEMPLATE

          def initialize(name = nil, ref = nil)
            @name = name
            @ref = ref
          end

          def to_xml_mapping(indent = @indent)
            if Utils.present?(@ref)
              "#{indent}import_model_mappings :#{Utils.snake_case(base_name)}\n"
            else
              @instance.to_xml_mapping(indent * 2)
            end
          end

          def to_class(options: {})
            setup_options(options)
            GROUP_TEMPLATE.result(binding)
          end

          def required_files
            if Utils.blank?(name) && Utils.present?(ref)
              "require_relative \"#{Utils.snake_case(ref.split(':').last)}\""
            else
              @instance&.required_files
            end
          end

          def to_attributes(indent = @indent)
            if Utils.present?(@ref)
              "#{indent}import_model_attributes :#{Utils.snake_case(base_name)}\n"
            else
              @instance.to_attributes(indent)
            end
          end

          def base_name
            (name || ref)&.split(":")&.last
          end

          private

          def setup_options(options)
            @indent = " " * options&.fetch(:indent, 2)
          end

          def definitions_content
            @definitions_content ||= instance.to_attributes(@indent)
          end

          def extended_indent
            @indent * 2
          end

          def xml_mapping_block
            XML_MAPPING_TEMPLATE.result(binding)
          end

          # Generate XML mapping content, unwrapping sequence for importable groups
          def xml_mapping_content
            return "" unless instance

            # For Groups (importable models without root), unwrap sequence content
            # because sequence requires a root element
            if instance.is_a?(Sequence)
              # Output sequence content directly without the wrapper
              instance.send(:xml_block_content, extended_indent)
            else
              instance.to_xml_mapping(extended_indent)
            end
          end
        end
      end
    end
  end
end
