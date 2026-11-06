# frozen_string_literal: true

require_relative "bundle"
require_relative "rejected_error"

module Lutaml
  module Model
    module Lml
      # Exports the closed graph of models reachable from some roots as a
      # Bundle (lutaml-model#1033, card 02b).
      #
      # One model is projected by an injected +projector+:
      #   projector.call(klass, register) -> v2 document Hash
      # where +register+ is the effective register string. The graph
      # follows model-typed attributes and discriminator cases by stable "Model@register" ID. Each ID is
      # projected once, so cycles terminate; the same ID with a different
      # definition, or a target that cannot be resolved, is rejected.
      # No state is kept between calls, so two registers never
      # contaminate each other.
      class GraphExporter
        REGISTER_FORMAT = /\A[A-Za-z0-9_.:-]+\z/
        DEFAULT_REGISTER = "default"
        # Keys whose values are user data (defaults, enum values, key
        # mappings), never structure: a data hash that merely looks like a
        # {"kind"=>"model"} reference must not be walked as one.
        DATA_KEYS = %w[default values child_mappings root_mappings].freeze

        def self.export(roots, projector:, register: nil, resolver: nil,
                        provenance: nil, check_root_registers: false, names: nil)
          new(register: register, projector: projector, resolver: resolver,
              check_root_registers: check_root_registers, names: names)
            .export(roots, provenance: provenance)
        end

        # Default resolver: the named constant, with the register's
        # type substitution applied when one is registered.
        def self.default_resolver(model_name, register)
          klass = Object.const_get(model_name)
          substitute(klass, register) || klass
        rescue NameError
          nil
        end

        def self.substitute(klass, register)
          return nil if register == DEFAULT_REGISTER
          return nil unless defined?(Lutaml::Model::GlobalRegister)

          reg = Lutaml::Model::GlobalRegister.lookup(register)
          reg&.substitute(klass)
        end

        # +names+ (klass -> String, default the class's own name) is the
        # identifier space the IDs live in; it must match the projector's.
        def initialize(projector:, register: nil, resolver: nil,
                       check_root_registers: false, names: nil)
          @names = names || Exporter::DEFAULT_NAMES
          @default_register = register
          @check_root_registers = check_root_registers
          @projector = projector
          @resolver = resolver || self.class.method(:default_resolver)
        end

        # +roots+: classes, or [class, register] pairs.
        def export(roots, provenance: nil)
          reject_unregistered!(@default_register)
          documents = {}
          owners = {}
          queue = []
          root_ids = Array(roots).map do |root|
            klass, register = root.is_a?(Array) ? root : [root, nil]
            reject_unregistered!(register) if @check_root_registers
            id = id_for(klass, effective_register(klass, register))
            queue << [id, klass]
            id
          end

          until queue.empty?
            id, klass = queue.shift
            next if owners[id].equal?(klass)

            doc = project(id, klass)
            if documents.key?(id)
              next if documents[id] == doc

              reject(:duplicate_id, id, "#{owners[id]} and #{klass} define it differently")
            end
            owners[id] = klass
            documents[id] = doc
            references(doc).each do |target|
              queue << [target, resolve(target, id)] unless owners.key?(target)
            end
          end

          value_types = collect_value_types(documents)
          check_references!(documents, value_types)
          Bundle.new(roots: root_ids, models: documents,
                     value_types: value_types, provenance: provenance)
        end

        private

        # A caller-supplied register (the default, or a root pair's when
        # +check_root_registers+ is set) must exist; silently exporting
        # under an unregistered name would mint Model@nosuch IDs no importer
        # could resolve. Registers a model declares itself are not checked,
        # and the round-trip replays a bundle's own identifiers with
        # +check_root_registers+ off.
        def reject_unregistered!(register)
          register = register.to_s
          return if register.empty? || register == DEFAULT_REGISTER || !REGISTER_FORMAT.match?(register)
          return if defined?(Lutaml::Model::GlobalRegister) && Lutaml::Model::GlobalRegister.lookup(register)

          reject(:invalid_document, register, "register #{register.inspect} is not registered")
        end

        def effective_register(klass, register)
          register ||= @default_register
          if register.nil? && klass.respond_to?(:lutaml_default_register)
            register = klass.lutaml_default_register
          end
          register = register.to_s
          register = DEFAULT_REGISTER if register.empty?
          return register if REGISTER_FORMAT.match?(register)

          reject(:invalid_document, klass, "register #{register.inspect} is not portable")
        end

        def id_for(klass, register)
          name = klass.respond_to?(:name) ? @names.call(klass) : nil
          if name.nil? || name.empty?
            reject(:invalid_document, klass, "anonymous class has no portable model name")
          end
          "#{name}@#{register}"
        end

        def split_id(id)
          model, _, register = id.rpartition("@")
          [model, register]
        end

        def resolve(target, referrer)
          model, register = split_id(target)
          klass = @resolver.call(model, register)
          return klass if klass

          reject(:dangling_reference, target, "referenced from #{referrer}")
        end

        def project(id, klass)
          model, register = split_id(id)
          doc = deep_copy(@projector.call(klass, register))
          unless doc.is_a?(::Hash)
            reject(:invalid_document, id, "projector returned #{doc.class}, not a Hash")
          end

          # A substituted class keeps the schema ID of the type it
          # replaced; anything else must agree with the ID.
          if @names.call(klass) == model
            check_identity!(id, doc, model, register)
          else
            doc["model"] = model
            doc["register"] = register
          end
          doc
        end

        def check_identity!(id, doc, model, register)
          return if doc["model"] == model && doc["register"].to_s == register

          reject(:invalid_document, id,
                 "document identifies as #{doc['model']}@#{doc['register']}")
        end

        # Model IDs this document points at: model-typed attributes and
        # discriminator cases.
        def references(node, found = [])
          case node
          when ::Hash
            found << node["id"] if node["kind"] == "model" && node["id"]
            collect_discriminator(node["discriminator"], found)
            node.each { |key, value| references(value, found) unless DATA_KEYS.include?(key) }
          when Array
            node.each { |value| references(value, found) }
          end
          found.uniq
        end

        def collect_discriminator(disc, found)
          return unless disc.is_a?(::Hash) && disc["cases"].is_a?(::Hash)

          found.concat(disc["cases"].values.grep(::String))
        end

        def value_type_ids(node, found = [])
          case node
          when ::Hash
            found << node["id"] if node["kind"] == "value" && node["id"]
            node.each { |key, value| value_type_ids(value, found) unless DATA_KEYS.include?(key) }
          when Array
            node.each { |value| value_type_ids(value, found) }
          end
          found
        end

        # Per-model "value_types" are hoisted to the bundle; the same ID
        # with two different definitions is a duplicate identity.
        def collect_value_types(documents)
          documents.each_with_object({}) do |(id, doc), merged|
            (doc.delete("value_types") || {}).each do |vid, definition|
              if merged.key?(vid) && merged[vid] != definition
                reject(:duplicate_id, id, "value type #{vid} defined twice differently")
              end
              merged[vid] = definition
            end
          end
        end

        def check_references!(documents, value_types)
          documents.each do |id, doc|
            references(doc).each do |target|
              next if documents.key?(target)

              reject(:dangling_reference, id, "unknown model #{target}")
            end
            value_type_ids(doc).each do |vid|
              next if value_types.key?(vid)

              reject(:dangling_reference, id, "unknown value type #{vid}")
            end
          end
        end

        def reject(reason, subject, detail)
          raise RejectedError.new(reason, subject, detail)
        end

        def deep_copy(node)
          case node
          when ::Hash then node.to_h { |k, v| [k.to_s, deep_copy(v)] }
          when Array then node.map { |item| deep_copy(item) }
          when ::String then node.dup
          else node
          end
        end
      end
    end
  end
end
