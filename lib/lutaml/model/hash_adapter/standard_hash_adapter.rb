require_relative "hash_document"

module Lutaml
  module Model
    module HashAdapter
      class StandardHashAdapter < HashDocument
        PERMITTED_CLASSES_BASE = [Date, Time, DateTime, Symbol, Hash,
                                  Array].freeze

        PERMITTED_CLASSES = if defined?(BigDecimal)
                              PERMITTED_CLASSES_BASE + [BigDecimal]
                            else
                              PERMITTED_CLASSES_BASE
                            end.freeze

        def self.parse(hsh, _options = {})
          hsh
        end

        def to_hash(_options = {})
          @attributes
        end
      end
    end
  end
end
