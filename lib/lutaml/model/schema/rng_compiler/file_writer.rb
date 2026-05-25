# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Thin RNG-side adapter over the shared
        # Lutaml::Model::Schema::FileWriter. Wires the RNG-specific
        # RegistryGenerator subclass into the shared writer.
        class FileWriter
          def self.write(output, dir)
            Lutaml::Model::Schema::FileWriter.write(
              output, dir, registry_generator: RegistryGenerator
            )
          end
        end
      end
    end
  end
end
