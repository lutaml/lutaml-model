# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      # Pure value object holding the output of compilation. No I/O — just
      # data. FileWriter / ClassLoader collaborators consume this to perform
      # the impure parts of `to_models`. Shared across schema compilers (RNG,
      # XSD, future formats).
      #
      # Entries are an ordered list of tagged records, each carrying a
      # CamelCase class name, a payload (either a Definitions::* spec or a
      # pre-rendered Ruby source String), and a `kind` of `:model` or
      # `:namespace`.
      #
      # `:model` entries are written to disk AND registered with
      # `register_all`. `:namespace` entries are written and autoloaded but
      # never registered.
      class CompiledOutput
        Entry = Struct.new(:name, :payload, :kind)

        attr_reader :entries, :module_namespace, :register_id,
                    :source_module_namespace

        # `module_namespace` is what the central registry file wraps in
        # (and where `register_all` lives). `source_module_namespace`
        # is what the per-class files wrap in — defaults to the same,
        # but ClassLoader can pass a different value when the caller
        # asked for unwrapped classes but a registry constant is still
        # needed to drive autoload.
        def initialize(entries:, module_namespace: nil, register_id: :default,
                       source_module_namespace: :inherit)
          @entries = entries
          @module_namespace = module_namespace
          @register_id = register_id
          @source_module_namespace =
            source_module_namespace == :inherit ? module_namespace : source_module_namespace
        end

        # Model-only entries — what the registry generator and ClassLoader
        # iterate when emitting `register_all` calls.
        def models
          @models ||= entries.select { |e| e.kind == :model }
        end

        # Namespace-only entries — autoloaded but never registered.
        def namespaces
          @namespaces ||= entries.select { |e| e.kind == :namespace }
        end

        # Flat `name => Ruby source` hash covering every entry (models +
        # namespaces). Used by FileWriter for the per-file write loop and
        # by RNG / XSD compilers as the public `to_models` return value.
        # Class files are rendered against `source_module_namespace`,
        # which usually equals `module_namespace` but differs when the
        # caller wanted unwrapped class files inside a registry module.
        def sources
          @sources ||= entries.to_h { |e| [e.name, source_for(e)] }
        end

        private

        def source_for(entry)
          renderer_for(entry.payload).render(
            entry.payload,
            module_namespace: @source_module_namespace,
            register_id: @register_id,
          )
        end

        def renderer_for(spec)
          case spec
          when Definitions::Model          then Renderers::Model
          when Definitions::RestrictedType then Renderers::RestrictedType
          when Definitions::UnionType      then Renderers::Union
          when Definitions::Namespace      then Renderers::Namespace
          else raise ArgumentError, "Unknown spec type: #{spec.class}"
          end
        end
      end
    end
  end
end
