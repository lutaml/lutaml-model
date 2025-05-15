# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module SharedMethods
        def lookup_register(register)
          return register.id if register.is_a?(Lutaml::Model::Register)

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
