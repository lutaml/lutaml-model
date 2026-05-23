# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Writes a CompiledOutput to a temporary directory, requires the
        # registry, and runs `register_all` so the generated classes are
        # loaded into a real module the caller can use immediately. Mirrors
        # XmlCompiler's load_classes mode.
        class ClassLoader
          def self.load(output)
            new(output).load
          end

          def initialize(output)
            # Force a module namespace; load_classes is only meaningful when
            # we're loading into a real module.
            module_ns = output.module_namespace || "GeneratedModels"
            @output = CompiledOutput.new(
              classes: output.classes,
              sources: rerender_with_namespace(output, module_ns),
              module_namespace: module_ns,
              register_id: output.register_id,
            )
          end

          def load
            Dir.mktmpdir do |dir|
              FileWriter.write(@output, dir)
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

          # If the original sources weren't rendered with a module_namespace
          # (e.g. user called `load_classes: true` without setting one),
          # re-render so the namespace wrap and registry references line up.
          def rerender_with_namespace(output, module_ns)
            return output.sources if output.module_namespace == module_ns

            output.classes.transform_values do |gen|
              gen.render(module_namespace: module_ns, register_id: output.register_id)
            end
          end
        end
      end
    end
  end
end
