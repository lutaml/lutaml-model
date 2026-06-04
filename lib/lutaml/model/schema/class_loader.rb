# frozen_string_literal: true

require "fileutils"
require "tmpdir"

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
          # Force a module namespace; load_classes is only meaningful when
          # we're loading into a real module. Building a fresh CompiledOutput
          # with the new module_namespace causes renderer-backed entries to
          # re-render against the new namespace when `sources` is called.
          module_ns = output.module_namespace || DEFAULT_NAMESPACE
          @output = CompiledOutput.new(
            entries: output.entries,
            module_namespace: module_ns,
            register_id: output.register_id,
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
