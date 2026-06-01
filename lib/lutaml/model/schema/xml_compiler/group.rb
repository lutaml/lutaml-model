# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # XSD Group -> Lutaml::Model::Serializable subclass (importable
        # type-only model — uses `type_name` instead of `element`).
        #
        # All rendering flow + hook defaults live in
        # Lutaml::Model::Schema::SerializableRenderer; only Group-specific
        # behavior is overridden here.
        class Group < Lutaml::Model::Schema::SerializableRenderer
          attr_accessor :name, :ref, :instance

          def initialize(name = nil, ref = nil)
            super()
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

          def required_files
            if Utils.blank?(name) && Utils.present?(ref)
              ["require_relative \"#{Utils.snake_case(ref.split(':').last)}\""]
            else
              Array(@instance&.required_files).flatten.compact.uniq
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

          # --- SerializableRenderer overrides ---

          # Group is never module-wrapped and always emits registration.
          def module_wrappable?
            false
          end

          # Group uses `@register ||=` memoization.
          def registration_lazy?
            true
          end

          def rendered_class_name
            Utils.camel_case(base_name)
          end

          def serializable_class_required_files
            files = required_files
            files.empty? ? "" : "\n#{files.join("\n")}\n"
          end

          def serializable_class_attributes
            instance.to_attributes(@indent)
          end

          # Groups use `type_name` (importable, no root).
          def xml_root_directive_line
            %(type_name "#{base_name}")
          end

          def xml_attribute_mappings
            return "" unless instance

            # For Groups (importable models without root), unwrap sequence
            # content because sequence requires a root element.
            if instance.is_a?(Sequence)
              instance.xml_block_content(@extended_indent)
            else
              instance.to_xml_mapping(@extended_indent)
            end
          end
        end
      end
    end
  end
end
