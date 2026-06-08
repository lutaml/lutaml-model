# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Renderers
        # Stateless helper for emitting the `self.register` and
        # `self.register_class_with_id` method block and the trailing
        # execution line, shared by the Model, RestrictedType, and Union
        # renderers. Module-namespaced classes skip both.
        module Registration
          module_function

          def methods_block(class_name:, module_namespace:, indent:, lazy: false)
            return "" if module_namespace

            target = Utils.snake_case(class_name).to_sym
            register_body = lazy ? "@register ||= Lutaml::Model::Config.default_register" : "Lutaml::Model::Config.default_register"
            <<~REG.gsub(/^/, indent)

              def self.register
              #{indent}#{register_body}
              end

              def self.register_class_with_id
              #{indent}context = Lutaml::Model::GlobalContext.context(Lutaml::Model::Config.default_register)
              #{indent}context.registry.register(:#{target}, self)
              end
            REG
          end

          def execution_line(class_name:, module_namespace:)
            return "" if module_namespace

            "\n#{class_name}.register_class_with_id\n"
          end
        end
      end
    end
  end
end
