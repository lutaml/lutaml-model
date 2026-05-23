# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Shared rendering helpers used by every generated-class kind:
        # GeneratedClass, SimpleType, UnionType, Namespace. Consolidates the
        # module open/close wrapper and the registration block boilerplate
        # so each renderer doesn't redefine ~70 lines of identical code.
        #
        # Hosts assume `@indent` (Integer), `@module_namespace` (String or
        # nil), `@register_id` (Symbol), and `@modules` (Array<String>)
        # instance variables — set inside `render(...)` like XmlCompiler does.
        module ClassBoilerplate
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

          # Generated `def self.register` + `def self.register_class_with_id`
          # methods. Skipped when a module namespace is active (the central
          # registry handles registration in that mode).
          def registration_methods(register_target_symbol = nil)
            return "" if @module_namespace

            sp_str = " " * @indent
            target = register_target_symbol || Utils.snake_case(class_name).to_sym

            <<~REG.gsub(/^/, sp_str)

              def self.register
              #{sp_str}Lutaml::Model::Config.default_register
              end

              def self.register_class_with_id
              #{sp_str}context = Lutaml::Model::GlobalContext.context(Lutaml::Model::Config.default_register)
              #{sp_str}context.registry.register(:#{target}, self)
              end
            REG
          end

          def registration_execution
            return "" if @module_namespace

            "\n#{class_name}.register_class_with_id\n"
          end
        end
      end
    end
  end
end
