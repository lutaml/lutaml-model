# frozen_string_literal: true

require "fileutils"

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Writes a CompiledOutput to disk: per-class .rb files in a module
        # subdirectory plus a central `*_registry.rb` (when a module
        # namespace is set). Mirrors XmlCompiler's create_files behavior.
        class FileWriter
          def self.write(output, dir)
            new(output, dir).write
          end

          def initialize(output, dir)
            @output = output
            @dir = dir
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

            registry = RegistryGenerator.generate(
              @output.classes,
              module_namespace: @output.module_namespace,
              register_id: @output.register_id,
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
            @output.sources.each do |name, src|
              File.write(File.join(target_dir, "#{Utils.snake_case(name)}.rb"), src)
            end
          end
        end
      end
    end
  end
end
