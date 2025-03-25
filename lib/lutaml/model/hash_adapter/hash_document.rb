# frozen_string_literal: true

require_relative "hash_object"

module Lutaml
  module Model
    module HashAdapter
      # Base class for Hash documents
      class HashDocument < HashObject
        def self.parse(hsh, _options = {})
          raise NotImplementedError, "Subclasses must implement `parse`."
        end

        def to_hash(*args)
          raise NotImplementedError, "Subclasses must implement `to_hash`."
        end
      end
    end
  end
end
