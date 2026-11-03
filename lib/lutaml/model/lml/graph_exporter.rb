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
      # follows model-typed attributes, discriminator cases and
      # reference targets by stable "Model@register" ID. Each ID is
      # projected once, so cycles terminate; the same ID with a different
      # definition, or a target that cannot be resolved, is rejected.
      # No state is kept between calls, so two registers never
      # contaminate each other.
      class GraphExporter
        REGISTER_FORMAT = /\A[A-Za-z0-9_.:-]+\z/
        DEFAULT_REGISTER = "default"

        def self.export(roots, projector:, register: nil, resolver: nil,
                        provenance: nil)
          new(register: register, projector: projector, resolver: resolver)
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
        rescue StandardError
          nil
        end

        def initialize(projector:, register: nil, resolver: nil)
          @default_register = register
          @projector = projector
          @resolver = resolver || self.class.method(:default_resolver)
        end

        # +roots+: classes, or [class, register] pairs.
        def export(roots, provenance: nil)
          documents = {}
          owners = {}
          queue = []
          root_ids = Array(roots).map do |root|
            klass, register = root.is_a?(Array) ? root : [root, nil]
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
          name = klass.respond_to?(:name) ? klass.name : nil
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
          if klass.name == model
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

        # Model IDs this document points at: model-typed attributes,
        # discriminator cases and reference targets.
        def references(node, found = [])
          case node
          when ::Hash
            found << node["id"] if node["kind"] == "model" && node["id"]
            collect_discriminator(node["discriminator"], found)
            collect_reference(node["reference"], found)
            node.each_value { |value| references(value, found) }
          when Array
            node.each { |value| references(value, found) }
          end
          found.uniq
        end

        def collect_discriminator(disc, found)
          return unless disc.is_a?(::Hash) && disc["cases"].is_a?(::Hash)

          found.concat(disc["cases"].values.grep(::String))
        end

        def collect_reference(ref, found)
          case ref
          when ::String then found << ref
          when ::Hash then found << (ref["model"] || ref["id"]) if (ref["model"] || ref["id"]).is_a?(::String)
          end
        end

        def value_type_ids(node, found = [])
          case node
          when ::Hash
            found << node["id"] if node["kind"] == "value" && node["id"]
            node.each_value { |value| value_type_ids(value, found) }
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
