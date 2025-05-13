# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module SharedMethods
        def lookup_register(register)
          return register.id if register.is_a?(Lutaml::Model::Register)

          register.nil? ? Lutaml::Model::Config.default_register : register
        end
      end
    end
  end
end
