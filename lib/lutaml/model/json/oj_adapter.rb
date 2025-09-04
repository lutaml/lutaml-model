require "oj"
require_relative "document"

module Lutaml
  module Model
    module Json
      class OjAdapter < Document
        def self.parse(json, _options = {})
          Oj.load(json)
        end

        def to_json(*args)
          Oj.dump(to_h, *args)
        end
      end
    end
  end
end
