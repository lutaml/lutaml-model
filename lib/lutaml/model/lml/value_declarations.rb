# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      # Caller-owned declarations for trusted named scalar classes. This is
      # data, not an inference about Ruby callbacks or an executable binding.
      class ValueDeclarations
        VERSION = 1
        attr_reader :version

        def initialize(entries, version: VERSION)
          unless version.is_a?(::Integer) && version == VERSION
            raise RejectedError.new(:unsupported_version, nil, "unsupported named-value declaration registry version")
          end
          unless entries.is_a?(::Hash)
            raise RejectedError.new(:invalid_document, nil, "named-value declarations require a class-keyed Hash")
          end

          @version = version
          @entries = entries.each_with_object({}) do |(klass, definition), out|
            unless klass.is_a?(::Class) && klass < Lutaml::Model::Type::Value && klass.name && !klass.name.empty?
              raise RejectedError.new(:unsupported_type, nil, "named-value declaration keys must be named scalar classes")
            end

            spec = data_copy(definition)
            tree = DocumentValidator.validate!({
                                                 "lml_bundle" => 1, "roots" => [], "models" => {},
                                                 "value_types" => { "#{klass.name}@default" => spec }, "capabilities" => []
                                               }, kind: :bundle)
            out[klass] = freeze_tree(tree.fetch("value_types").fetch("#{klass.name}@default"))
          end.freeze
          freeze
        end

        # Class identity is exact: names, aliases, subclasses and strings never
        # gain a declaration merely because their spelling resembles a key.
        def fetch(klass)
          @entries[klass]
        end

        def to_h
          { "version" => version,
            "types" => @entries.sort_by { |klass, _| klass.name }.to_h { |klass, spec| [klass.name, spec] } }
        end

        private

        def data_copy(value, depth = 0)
          if depth >= DocumentValidator::MAX_DEPTH
            raise RejectedError.new(:invalid_document, nil, "named-value declaration nesting exceeds limit")
          end

          case value
          when ::Hash
            value.to_h do |key, item|
              unless key.is_a?(::String)
                raise RejectedError.new(:invalid_document, nil, "named-value declaration keys must be strings")
              end

              [key.dup, data_copy(item, depth + 1)]
            end
          when ::Array then value.map { |item| data_copy(item, depth + 1) }
          when ::String then value.dup
          when ::Integer, ::Float, true, false, nil then value
          else
            raise RejectedError.new(:invalid_document, nil, "named-value declarations contain data only")
          end
        end

        def freeze_tree(value)
          case value
          when ::Hash then value.each do |key, item| 
            key.freeze
            freeze_tree(item)
          end
          when ::Array then value.each { |item| freeze_tree(item) }
          end
          value.freeze
        end
      end
    end
  end
end
