# frozen_string_literal: true

require "erb"

module Lutaml
  module Model
    module Schema
      # Base class for per-format registry generators (one Ruby file that
      # declares autoloads + a `self.register_all` that registers every
      # generated class with the model registry).
      #
      # Subclasses customize the ERB skeleton (e.g., XSD adds import
      # resolution phases) but inherit the shared module-wrap and
      # autoload/registration emit methods.
      class RegistryGenerator
        DEFAULT_TEMPLATE = ERB.new(<<~TMPL, trim_mode: "-")
          # frozen_string_literal: true
          # Auto-generated central registry for <%= @module_namespace %>

          <%= module_opening -%>
          <%= autoload_declarations %>

            def self.register_all
              context = Lutaml::Model::GlobalContext.context(:<%= @register_id %>) ||
                        Lutaml::Model::GlobalContext.create_context(id: :<%= @register_id %>)

          <%= registration_body %>
            end
          <%= module_closing -%>
        TMPL

        def self.generate(model_entries, options = {})
          new(model_entries, options).generate
        end

        # `model_entries` is an Array of CompiledOutput::Entry with kind
        # `:model`. `options[:namespaces]` is an Array of `:namespace`
        # entries, autoloaded but never registered.
        def initialize(model_entries, options)
          @classes = model_entries
          @namespaces = options[:namespaces] || []
          @module_namespace = options[:module_namespace]
          @register_id = options[:register_id] || :default
          @modules = @module_namespace&.split("::") || []
        end

        def generate
          return nil unless @module_namespace

          template.result(binding)
        end

        private

        # Subclasses can override to use a different ERB skeleton.
        def template
          self.class::DEFAULT_TEMPLATE
        end

        # The body of `def self.register_all`. Default is just the
        # registration block; subclasses can override to add extra phases
        # (e.g., XSD's ensure_imports! / ensure_mappings_imported! passes).
        def registration_body
          registration_calls
        end

        # Inside-`register_all` indent, used by phase-comment overrides.
        def body_indent
          "  " * (module_depth + 1)
        end

        # Autoload every generated constant: model classes AND namespace
        # classes. Models are then registered with `register_all`;
        # namespaces are only autoloaded (model classes reference them
        # in their `namespace ...` mapping declarations).
        def autoload_declarations
          indent = "  " * module_depth
          module_subdir = @module_namespace.split("::").last.downcase
          (@classes + @namespaces).map do |entry|
            class_name = Utils.camel_case(entry.name)
            file_name = Utils.snake_case(entry.name)
            "#{indent}autoload :#{class_name}, " \
              "File.join(__dir__, \"#{module_subdir}\", \"#{file_name}\")"
          end.join("\n")
        end

        def registration_calls
          indent = "  " * (module_depth + 1)
          @classes.map do |entry|
            class_name = Utils.camel_case(entry.name)
            id = Utils.snake_case(entry.name).to_sym
            "#{indent}#{class_name} # Trigger autoload\n" \
              "#{indent}context.registry.register(:#{id}, #{class_name})\n" \
              "#{indent}#{class_name}.instance_variable_set(:@register, :#{@register_id})"
          end.join("\n")
        end

        # Thin forwarders so the ERB template using `<%= module_opening %>`
        # / `<%= module_closing %>` keeps working. Logic lives in
        # `Lutaml::Model::Schema::ModuleNesting`.
        def module_opening
          ModuleNesting.opening(Array(@modules))
        end

        def module_closing
          ModuleNesting.closing(Array(@modules))
        end

        def module_depth
          @modules.size
        end
      end
    end
  end
end
