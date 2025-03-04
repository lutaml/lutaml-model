# frozen_string_literal: true

module Lutaml
  module Model
    class Register
      class << self
        def register
          @register ||= {}
        end

        def register_model(type, type_class)
          register[type.to_sym] = type_class
        end

        def lookup!(type)
          case type
          when Symbol
            klass = register[type]
            raise UnknownTypeError.new(type) if klass.nil?

            klass
          when String
            begin
              Type.const_get(type)
            rescue NameError
              raise UnknownTypeError.new(type)
            end
          when Class
            type
          else
            raise UnknownTypeError.new(type)
          end
        end

        def add_attribute(
          model_path:,
          attribute:,
          type:
        )
          # TODO: integrate lutaml-path for this method
          # model = Lutaml::Path.find(model_path)
          # model.add_attribute(attribute, type)
        end

        def remove_attribute(
          model_path:,
          attribute:
        )
          # TODO: integrate lutaml-path for this method
          # model = Lutaml::Path.find(model_path)
          # model.remove_attribute(attribute)
        end

        def resolve(class_str)
          # TODO: integrate lutaml-path for this method
        end

        def resolve_path(class_str)
          # TODO: integrate lutaml-path for this method
        end
      end
    end
  end
end
