# frozen_string_literal: true

require "erb"

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class RegistryGenerator
          def self.generate(classes_hash, options = {})
            new(classes_hash, options).generate
          end

          def initialize(classes_hash, options)
            @classes = classes_hash
            @module_namespace = options[:module_namespace]
            @register_id = options[:register_id] || :default
          end

          def generate
            return nil unless @module_namespace

            template.result(binding)
          end

          private

          def template
            ERB.new(<<~TEMPLATE, trim_mode: "-")
              # frozen_string_literal: true
              # Auto-generated central registry for <%= @module_namespace %>

              <%= module_opening %>
              <%= autoload_declarations %>

                def self.register_all
                  register = Lutaml::Model::GlobalRegister.lookup(:<%= @register_id %>)

                  # Phase 1: Register all models (no imports)
              <%= registration_calls %>

                  # Phase 2: Resolve model, choice, and restrict imports
              <%= model_import_resolution_calls %>

                  # Phase 3: Resolve mapping and sequence imports
              <%= mapping_import_resolution_calls %>
                end
              <%= module_closing %>
            TEMPLATE
          end

          def module_opening
            modules = @module_namespace.split("::")
            modules.map.with_index { |mod, i| "#{'  ' * i}module #{mod}" }.join("\n")
          end

          def module_closing
            modules = @module_namespace.split("::")
            modules.reverse.map.with_index { |_mod, i| "#{'  ' * (modules.size - i - 1)}end" }.join("\n")
          end

          def autoload_declarations
            indent = "  " * module_depth
            @classes.keys.map do |name|
              # Skip namespace classes (check the name, not the content)
              next if name.to_s.include?("Namespace")

              class_name = Utils.camel_case(name)
              file_name = Utils.snake_case(name)
              # Use relative path from registry file location
              module_subdir = @module_namespace.split("::").last.downcase
              "#{indent}autoload :#{class_name}, File.join(__dir__, \"#{module_subdir}\", \"#{file_name}\")"
            end.compact.join("\n")
          end

          def registration_calls
            indent = "  " * (module_depth + 1)
            @classes.keys.map do |name|
              # Skip namespace classes (check the name, not the content)
              next if name.to_s.include?("Namespace")

              class_name = Utils.camel_case(name)
              id = Utils.snake_case(name).to_sym
              "#{indent}#{class_name} # Trigger autoload\n#{indent}register.register_model(#{class_name}, id: :#{id})\n#{indent}#{class_name}.instance_variable_set(:@register, :#{@register_id})"
            end.compact.join("\n")
          end

          def model_import_resolution_calls
            indent = "  " * (module_depth + 1)
            "\n#{indent}# Resolve model structure imports (attributes, choices)\n" +
            @classes.keys.map do |name|
              next if name.to_s.include?("Namespace")

              class_name = Utils.camel_case(name)
              "#{indent}#{class_name}.ensure_imports!(:#{@register_id}) if #{class_name}.respond_to?(:ensure_imports!)"
            end.compact.join("\n")
          end

          def mapping_import_resolution_calls
            indent = "  " * (module_depth + 1)
            "\n#{indent}# Resolve serialization mapping imports (sequence imports)\n" +
            @classes.keys.map do |name|
              next if name.to_s.include?("Namespace")
              next unless @classes[name].respond_to?(:mappings)

              class_name = Utils.camel_case(name)
              "#{indent}#{class_name}.mappings[:xml].ensure_mappings_imported!(:#{@register_id}) if #{class_name}.mappings[:xml]&.respond_to?(:ensure_mappings_imported!)"
            end.compact.join("\n")
          end

          def module_depth
            @module_namespace.split("::").size
          end

          def module_path
            @module_namespace.split("::").map(&:downcase).join("/")
          end
        end
      end
    end
  end
end