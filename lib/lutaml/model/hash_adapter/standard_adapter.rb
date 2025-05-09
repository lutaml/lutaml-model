require_relative "document"

module Lutaml
  module Model
    module HashAdapter
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
