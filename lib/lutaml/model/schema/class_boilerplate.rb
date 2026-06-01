# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      # Shared rendering helpers for generated-class boilerplate: the
      # module wrap (`module A; module B; ... end; end`) and the
      # `self.register` / `self.register_class_with_id` method pair plus
      # the trailing `Klass.register_class_with_id` execution line.
      #
      # Consumed by XSD compiler (ComplexType, SimpleType, Group,
      # XmlNamespaceClass) and RNG compiler (GeneratedClass, SimpleType,
      # UnionType, Namespace) — and available to any future format
      # compiler that generates Serializable subclasses.
      #
      # Hosts must expose:
      #   - `@modules`              Array<String> — module nesting (split of "Foo::Bar")
      #   - `@module_namespace`     String or nil — non-nil disables per-class registration
      #   - `@indent`               String — base indent (set by `setup_render_options`)
      #   - `#rendered_class_name`  method returning the generated class's CamelCase name
      module ClassBoilerplate
        # Shared options-handling for every renderer base class. Sets
        # `@indent` (String), `@extended_indent` (String, 2× indent),
        # `@module_namespace`, `@modules`, `@register_id` from the options
        # hash. Subclasses can override to extract extra format-specific
        # options after calling super.
        def setup_render_options(options)
          raw = options[:indent] || 2
          @indent = raw.is_a?(Integer) ? " " * raw : raw
          @extended_indent = @indent * 2
          if module_wrappable?
            @module_namespace = options[:module_namespace]
            @modules = @module_namespace&.split("::") || []
          else
            @module_namespace = nil
            @modules = []
          end
          @register_id = options[:register_id] || :default
        end

        # Whether the generated class is wrapped in `module X; ... end` and
        # has its registration suppressed when a module_namespace is set.
        # Defaults to true; subclasses (e.g. Group) override to false when
        # the generated class is always emitted flat with its own
        # registration regardless of namespace.
        def module_wrappable?
          true
        end

        # Whether `def self.register` uses `@register ||=` memoization
        # rather than direct assignment. Subclasses override to true when
        # they need lazy memoization (XSD SimpleType, Group).
        def registration_lazy?
          false
        end

        # When inside a `module_namespace`, whether to still emit just the
        # `def self.register` method (skipping `register_class_with_id`).
        # XSD simple-type renderers need this so union resolution can call
        # `register.get_class`. Defaults to false.
        def keep_register_when_namespaced?
          false
        end

        # Shared render entry point. Accepts both kwarg style
        # (`render(indent: 2, …)`) and positional hash style
        # (`render({indent: 2, …})`). Renderer bases must expose a
        # `template` method returning the ERB constant to evaluate.
        def render(options = {}, **kwargs)
          options = options.merge(kwargs) unless kwargs.empty?
          setup_render_options(options)
          template.result(binding)
        end

        # Compat alias used by callers that pass `to_class(options: ...)`.
        def to_class(options: {})
          render(options)
        end

        private

        def module_opening
          return "" if Array(@modules).empty?

          @modules.map.with_index { |m, i| "#{'  ' * i}module #{m}\n" }.join
        end

        def module_closing
          return "" if Array(@modules).empty?

          @modules.reverse.map.with_index do |_m, i|
            "#{'  ' * (@modules.size - i - 1)}end\n"
          end.join
        end

        # @param register_target_symbol [Symbol, nil] override for the
        #   registry symbol (defaults to snake_case(rendered_class_name))
        def registration_methods(register_target_symbol = nil)
          return "" if @module_namespace && !keep_register_when_namespaced?

          sp = boilerplate_indent_str
          register_body = if registration_lazy?
                            "@register ||= Lutaml::Model::Config.default_register"
                          else
                            "Lutaml::Model::Config.default_register"
                          end

          if @module_namespace
            <<~REG.gsub(/^/, sp)

              def self.register
              #{sp}#{register_body}
              end
            REG
          else
            target = register_target_symbol || Utils.snake_case(rendered_class_name).to_sym
            <<~REG.gsub(/^/, sp)

              def self.register
              #{sp}#{register_body}
              end

              def self.register_class_with_id
              #{sp}context = Lutaml::Model::GlobalContext.context(Lutaml::Model::Config.default_register)
              #{sp}context.registry.register(:#{target}, self)
              end
            REG
          end
        end

        def registration_execution
          return "" if @module_namespace

          "\n#{rendered_class_name}.register_class_with_id\n"
        end

        # The string indent for class body emission. `@indent` is always
        # a String after `setup_render_options`; `||` covers the rare
        # path where the renderer renders without going through it.
        def boilerplate_indent_str
          @indent || "  "
        end
      end
    end
  end
end
