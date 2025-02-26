# frozen_string_literal: true

module Lutaml
  module Model
    class Registry
      class << self
        def registry
          @registry ||= {}
        end

        def register(type, type_class)
          registry[type.to_sym] = type_class
        end

        def lookup!(type)
          case type
          when Symbol
            klass = registry[type]
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
      end
    end
  end
end
