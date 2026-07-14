# frozen_string_literal: true

unless RUBY_ENGINE == "opal"
  require "fileutils"
  require "tmpdir"
end

module Lutaml
  module Model
    module Schema
      # Writes a CompiledOutput to a temporary directory, requires the
      # registry, and runs `register_all` so the generated classes are
      # loaded into a real module the caller can use immediately. Shared
      # between XSD and RNG compilers.
      class ClassLoader
        DEFAULT_NAMESPACE = "GeneratedModels"

        def self.load(output, registry_generator: RegistryGenerator)
          new(output, registry_generator).load
        end

        def initialize(output, registry_generator)
          # ClassLoader needs a module to host the registry constant
          # (so `register_all` has a home). If the caller wanted
          # unwrapped class files, we still force a registry module —
          # but we pin `source_module_namespace` to what they asked for,
          # so per-class files keep their original wrapping.
          @output = CompiledOutput.new(
            entries: output.entries,
            module_namespace: output.module_namespace || DEFAULT_NAMESPACE,
            register_id: output.register_id,
            source_module_namespace: output.module_namespace,
          )
          @registry_generator = registry_generator
        end

        def load
          Dir.mktmpdir do |dir|
            FileWriter.write(@output, dir, registry_generator: @registry_generator)
            require File.join(dir, "#{registry_basename}_registry")
            call_register_all
          end
        end

        private

        def registry_basename
          @output.module_namespace.split("::").last.downcase
        end

        def call_register_all
          mod = Object.const_get(@output.module_namespace)
          mod.register_all if mod.respond_to?(:register_all)
        end
      end
    end
  end
end
