# frozen_string_literal: true

module Lutaml
  module Yamls
    module Adapter
      class YamlsSequenceRule
        attr_reader :position, :to, :type, :collection

        def initialize(position, to:, type:, collection: false)
          @position = position
          @to = to
          @type = type
          @collection = collection
        end

        def resolve_range(doc_count)
          return nil unless doc_count.positive?

          case position
          when Integer
            idx = position.negative? ? position + doc_count : position
            idx..idx
          when Range
            start_idx = position.begin.negative? ? position.begin + doc_count : position.begin
            end_idx = position.end
            end_idx = doc_count - 1 if end_idx.nil?
            end_idx = end_idx + doc_count if end_idx.negative?
            end_idx = doc_count - 1 if end_idx > doc_count - 1
            start_idx = 0 if start_idx.negative?
            start_idx..end_idx
          end
        end

        def singular?
          !collection
        end

        def assign_value(instance, value)
          instance.public_send(:"#{to}=", value)
        end

        def read_value(instance)
          instance.public_send(to)
        end
      end
    end
  end
end
