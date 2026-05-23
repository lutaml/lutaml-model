# frozen_string_literal: true

require "erb"

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Generates a central registry file matching XmlCompiler::RegistryGenerator.
        # Only used when :module_namespace is set.
        class RegistryGenerator
          TEMPLATE = ERB.new(<<~TMPL, trim_mode: "-")
            # frozen_string_literal: true
            # Auto-generated central registry for <%= @module_namespace %>

            <%= module_opening %>
            <%= autoload_declarations %>

              def self.register_all
                context = Lutaml::Model::GlobalContext.context(:<%= @register_id %>) ||
                          Lutaml::Model::GlobalContext.create_context(id: :<%= @register_id %>)

            <%= registration_calls %>
              end
            <%= module_closing %>
          TMPL

          def self.generate(classes_hash, options = {})
            new(classes_hash, options).generate
          end

          def initialize(classes_hash, options)
            @classes = classes_hash
            @module_namespace = options[:module_namespace]
            @register_id = options[:register_id] || :default
            @modules = @module_namespace&.split("::") || []
          end

          def generate
            return nil unless @module_namespace

            TEMPLATE.result(binding)
          end

          private

          def module_opening
            return "" if @modules.empty?

            @modules.map.with_index { |mod, i| "#{'  ' * i}module #{mod}" }.join("\n")
          end

          def module_closing
            return "" if @modules.empty?

            @modules.reverse.map.with_index do |_mod, i|
              "#{'  ' * (@modules.size - i - 1)}end"
            end.join("\n")
          end

          def autoload_declarations
            indent = "  " * module_depth
            module_subdir = @module_namespace.split("::").last.downcase
            @classes.keys.map do |name|
              class_name = Utils.camel_case(name)
              file_name = Utils.snake_case(name)
              "#{indent}autoload :#{class_name}, File.join(__dir__, \"#{module_subdir}\", \"#{file_name}\")"
            end.join("\n")
          end

          def registration_calls
            indent = "  " * (module_depth + 1)
            @classes.keys.filter_map do |name|
              # Namespace classes are autoloaded but not registered in the
              # model registry. Mirrors XmlCompiler::RegistryGenerator.
              next if name.to_s.include?("Namespace")

              class_name = Utils.camel_case(name)
              id = Utils.snake_case(name).to_sym
              "#{indent}#{class_name} # Trigger autoload\n" \
                "#{indent}context.registry.register(:#{id}, #{class_name})\n" \
                "#{indent}#{class_name}.instance_variable_set(:@register, :#{@register_id})"
            end.join("\n")
          end

          def module_depth
            @modules.size
          end
        end
      end
    end
  end
end
