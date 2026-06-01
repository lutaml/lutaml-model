# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # RNG registry generator. Uses the shared default template — RNG
        # generated classes have no import resolution phase, so the base
        # class's single-phase template is exactly what we want.
        class RegistryGenerator < Lutaml::Model::Schema::RegistryGenerator
        end
      end
    end
  end
end
