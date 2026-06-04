# frozen_string_literal: true

require "fileutils"

module Lutaml
  module Model
    module Schema
      # Writes a CompiledOutput to disk: per-class .rb files in a module
      # subdirectory plus a central `*_registry.rb` (when a module
      # namespace is set). Shared between XSD and RNG compilers.
      #
      # The `registry_generator:` parameter selects which RegistryGenerator
      # subclass to use (XSD has a 2-phase template; RNG uses the default).
      class FileWriter
        def self.write(output, dir, registry_generator: RegistryGenerator)
          new(output, dir, registry_generator).write
        end

        def initialize(output, dir, registry_generator)
          @output = output
          @dir = dir
          @registry_generator = registry_generator
        end

        def write
          if @output.module_namespace
            write_namespaced
          else
            write_flat
          end
        end

        private

        def write_namespaced
          module_path = @output.module_namespace.split("::").map(&:downcase).join("/")
          full_dir = File.join(@dir, module_path)
          FileUtils.mkdir_p(full_dir)

          registry = @registry_generator.generate(
            @output.models,
            module_namespace: @output.module_namespace,
            register_id: @output.register_id,
            namespaces: @output.namespaces,
          )
          if registry
            registry_name = module_path.split("/").last
            File.write(File.join(@dir, "#{registry_name}_registry.rb"), registry)
          end

          write_sources_to(full_dir)
        end

        def write_flat
          FileUtils.mkdir_p(@dir)
          write_sources_to(@dir)
        end

        def write_sources_to(target_dir)
          @output.sources.each { |name, src| write_source(target_dir, name, src) }
        end

        def write_source(target_dir, name, src)
          file_name = Utils.snake_case(Utils.last_of_split(name.to_s))
          File.write(File.join(target_dir, "#{file_name}.rb"), src)
        end
      end
    end
  end
end
