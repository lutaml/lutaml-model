# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Group
          attr_accessor :name, :ref, :instance

          GROUP_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true

            # Empty class initialization to avoid circular dependency issues.
            class <%= model_name %> < <%= base_class_name %>
              xml do
                no_root
              end
            end

            <%=  "\n" + required_files.uniq.join("\n") -%>

            class <%= model_name %> < <%= base_class_name %>
            <%= definitions_content -%>
            <%= xml_mapping_block -%>
            end
          TEMPLATE

          XML_MAPPING_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= @indent %>xml do
            <%= @indent * 2 %>no_root

            <%= instance.to_xml_mapping(@indent * 2) -%>
            <%= @indent %>end
          TEMPLATE

          IMPORT_MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= @indent %>import_model <%= model_name %>
          TEMPLATE

          def initialize(name = nil, ref = nil)
            @name = name
            @ref = ref
          end

          def to_xml_mapping(indent = @indent)
            if Utils.present?(@ref)
              "#{indent}import_model_mappings #{model_name}\n"
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
              "require_relative \"#{Utils.snake_case(ref.split(":").last)}\""
            else
              @instance&.required_files
            end
          end

          def to_attributes(indent = @indent)
            if Utils.present?(@ref)
              "#{indent}import_model_attributes #{model_name}\n"
            else
              @instance.to_attributes(indent)
            end
          end

          def model_name
            Utils.camel_case((name || ref)&.split(":")&.last)
          end

          private

          def base_class_name
            "Lutaml::Model::Serializable"
          end

          def setup_options(options)
            @indent = " " * options&.fetch(:indent, 2)
          end

          def definitions_content
            @definitions_content ||= instance.to_attributes(@indent)
          end

          def xml_mapping_block
            return unless definitions_content.include?("attribute :")

            XML_MAPPING_TEMPLATE.result(binding)
          end
        end
      end
    end
  end
end
