# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Group
          attr_accessor :id, :name, :maxOccurs, :minOccurs, :ref, :instance

          INDENT = "  "

          GROUP_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            class <%= model_name %> < Lutaml::Model::Serializable
            <%= definitions_content(indent) -%>
            <%= xml_mapping_block(indent) -%>
            end
          TEMPLATE

          XML_MAPPING_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>xml do
            <%= indent + INDENT %>no_root

            <%= instance.to_xml_mapping(indent + INDENT) -%>
            <%= indent %>end
          TEMPLATE

          IMPORT_MODEL_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>import_model <%= model_name %>
          TEMPLATE

          def initialize(name = nil, ref = nil)
            raise "Group name is required" if Utils.blank?(name) && Utils.blank?(ref)

            @name = name
            @ref = ref
          end

          def to_xml_mapping(indent = INDENT)
            # NO implementation for mapping is required for groups since these will be imported at attribute level
            nil
          end

          def to_class(indent = INDENT)
            GROUP_TEMPLATE.result(binding)
          end

          def required_files
            return if Utils.blank?(@name)

            @instance.required_files
          end

          def to_attributes(indent = INDENT)
            IMPORT_MODEL_TEMPLATE.result(binding)
          end

          def model_name
            Utils.camel_case((name || ref)&.split(":")&.last)
          end

          private

          def definitions_content(indent)
            @definitions_content ||= instance.to_attributes(indent)
          end

          def xml_mapping_block(indent)
            return unless definitions_content(indent).include?("attribute :")

            XML_MAPPING_TEMPLATE.result(binding)
          end
        end
      end
    end
  end
end
