# frozen_string_literal: true

module Lutaml
  module KeyValue
    module Adapter
      module Hash
        class StandardAdapter < Document
          def self.parse(hsh, _options = {})
            # from_hash's root contract: the document IS a hash. A
            # non-hash previously crashed deep in the value extractor
            # (a NoMethodError wrapped as InvalidFormatError); the
            # #1228 guard made that path reachable by scalar values for
            # mapped complex attributes, so the root validation lives
            # here where it belongs.
            unless hsh.respond_to?(:key?)
              raise Lutaml::Model::InvalidFormatError.new(
                :hash, "the document is not a Hash (got #{hsh.class})"
              )
            end

            hsh
          end

          def to_hash(_options = {})
            @attributes
          end
        end
      end
    end
  end
end
