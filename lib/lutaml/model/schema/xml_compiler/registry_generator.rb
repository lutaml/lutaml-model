# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # XSD registry generator. Extends the shared base with an extra
        # phase for resolving model imports — XSD-generated classes use
        # ensure_imports! hooks that need to run after every model is
        # registered.
        class RegistryGenerator < Lutaml::Model::Schema::RegistryGenerator
          private

          # Override the shared `registration_body` hook with two phases.
          def registration_body
            [
              "#{body_indent}# Phase 1: Register all models (no imports)",
              registration_calls,
              "",
              "#{body_indent}# Phase 2: Resolve model, choice, and restrict imports",
              model_import_resolution_calls,
            ].join("\n")
          end

          def model_import_resolution_calls
            @classes.map do |entry|
              class_name = Utils.camel_case(entry.name)
              "#{body_indent}#{class_name}.ensure_imports!(:#{@register_id}) " \
                "if #{class_name}.respond_to?(:ensure_imports!)"
            end.join("\n")
          end
        end
      end
    end
  end
end
