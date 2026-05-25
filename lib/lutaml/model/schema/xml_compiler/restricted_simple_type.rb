# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # XSD restricted simple-type renderer — for `<xs:simpleType>` with
        # `<xs:restriction>` (no union). Inherits the full render flow from
        # Lutaml::Model::Schema::RestrictedSimpleTypeRenderer.
        class RestrictedSimpleType < Lutaml::Model::Schema::RestrictedSimpleTypeRenderer
          include SimpleTypeBase

          attr_accessor :base_class, :instance

          def initialize(name)
            super()
            @class_name = name
            @module_namespace = nil
          end

          def required_files
            files = Array(instance&.required_files)
            if !@module_namespace && require_parent?
              files << "require_relative \"#{Utils.snake_case(parent_class)}\""
            end
            # When using autoload, only keep external requires.
            files = files.select { |f| f.start_with?("require \"") } if @module_namespace
            files.join("\n")
          end

          # --- RestrictedSimpleTypeRenderer overrides ---

          def parent_class
            type_info = SimpleType::SUPPORTED_DATA_TYPES[base_class&.to_sym]
            return type_info[:class_name] if type_info&.dig(:skippable)
            return Utils.camel_case(base_class.to_s) if !type_info&.dig(:skippable) && Utils.present?(base_class)

            "Lutaml::Model::Type::Value"
          end

          def restricted_simple_type_required_files
            files = required_files
            files.empty? ? "" : "#{files}\n"
          end

          def restricted_simple_type_cast_body
            instance&.to_method_body(boilerplate_indent_str * 2).to_s
          end

          private

          def require_parent?
            return false if Utils.blank?(base_class)

            !SimpleType::SUPPORTED_DATA_TYPES[base_class&.to_sym]&.dig(:skippable)
          end
        end
      end
    end
  end
end
