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
            if klass.nil?
              raise UnknownTypeError.new(type)
            else
              klass
            end
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
