# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Thin RNG-side adapter over the shared
        # Lutaml::Model::Schema::ClassLoader. Wires the RNG-specific
        # RegistryGenerator subclass into the shared loader.
        class ClassLoader
          def self.load(output)
            Lutaml::Model::Schema::ClassLoader.load(
              output, registry_generator: RegistryGenerator
            )
          end
        end
      end
    end
  end
end
