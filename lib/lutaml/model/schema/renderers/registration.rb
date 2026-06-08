# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Renderers
        # Stateless helper for emitting the `self.register` and
        # `self.register_class_with_id` method block plus the trailing
        # execution line, shared by the Model, RestrictedType, and Union
        # renderers.
        #
        # Cases:
        #   module_namespace = nil          -> emit both methods + execution
        #   namespace + keep_when_namespaced -> emit only `self.register`
        #   namespace + !keep              -> emit nothing
        module Registration
          module_function

          def methods_block(class_name:, module_namespace:, indent:,
                            lazy: false, keep_when_namespaced: false)
            return "" if module_namespace && !keep_when_namespaced
            return register_only_block(indent, lazy) if module_namespace

            full_block(class_name, indent, lazy)
          end

          def execution_line(class_name:, module_namespace:)
            return "" if module_namespace

            "\n#{class_name}.register_class_with_id\n"
          end

          def register_only_block(indent, lazy)
            <<~REG.gsub(/^/, indent)

              def self.register
              #{indent}#{register_body(lazy)}
              end
            REG
          end

          def full_block(class_name, indent, lazy)
            target = Utils.snake_case(class_name).to_sym
            <<~REG.gsub(/^/, indent)

              def self.register
              #{indent}#{register_body(lazy)}
              end

              def self.register_class_with_id
              #{indent}context = Lutaml::Model::GlobalContext.context(Lutaml::Model::Config.default_register)
              #{indent}context.registry.register(:#{target}, self)
              end
            REG
          end

          def register_body(lazy)
            lazy ? "@register ||= Lutaml::Model::Config.default_register" : "Lutaml::Model::Config.default_register"
          end
        end
      end
    end
  end
end
