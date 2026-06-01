# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # XSD registry generator. Extends the shared base with two extra
        # phases for resolving model and mapping imports — XSD-generated
        # classes use ensure_imports! / ensure_mappings_imported! hooks
        # that need to run after every model is registered.
        class RegistryGenerator < Lutaml::Model::Schema::RegistryGenerator
          private

          # Override the shared `registration_body` hook with three phases.
          def registration_body
            [
              "#{body_indent}# Phase 1: Register all models (no imports)",
              registration_calls,
              "",
              "#{body_indent}# Phase 2: Resolve model, choice, and restrict imports",
              model_import_resolution_calls,
              "",
              "#{body_indent}# Phase 3: Resolve mapping and sequence imports",
              mapping_import_resolution_calls,
            ].join("\n")
          end

          def model_import_resolution_calls
            @classes.keys.filter_map do |name|
              next if name.to_s.include?("Namespace")

              class_name = Utils.camel_case(name)
              "#{body_indent}#{class_name}.ensure_imports!(:#{@register_id}) " \
                "if #{class_name}.respond_to?(:ensure_imports!)"
            end.join("\n")
          end

          def mapping_import_resolution_calls
            @classes.keys.filter_map do |name|
              next if name.to_s.include?("Namespace")
              next unless @classes[name].is_a?(Class) &&
                @classes[name].include?(Lutaml::Model::Serialize)

              class_name = Utils.camel_case(name)
              "#{body_indent}#{class_name}.mappings[:xml].ensure_mappings_imported!(:#{@register_id}) " \
                "if #{class_name}.mappings[:xml]&.respond_to?(:ensure_mappings_imported!)"
            end.join("\n")
          end
        end
      end
    end
  end
end
