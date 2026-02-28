# frozen_string_literal: true

module Lutaml
  module KeyValue
    module Adapter
      module Hash
        class StandardAdapter < Document
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
end
