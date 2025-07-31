# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module SharedMethods
        def extract_register_from(klass)
          register = if klass.class_variable_defined?(:@@__register)
                       klass.class_variable_get(:@@__register)
                     end

          case register
          when Lutaml::Model::Register
            register.id
          when String, Symbol
            register.to_sym
          else
            Lutaml::Model::Config.default_register
          end
        end
      end
    end
  end
end
