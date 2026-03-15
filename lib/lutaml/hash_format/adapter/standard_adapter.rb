# frozen_string_literal: true

module Lutaml
  module HashFormat
    module Adapter
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
