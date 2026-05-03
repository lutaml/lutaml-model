# frozen_string_literal: true

module Lutaml
  module Yamls
    module Adapter
      class YamlsSequence
        attr_reader :rules

        def initialize
          @rules = []
        end

        def map_document(position, to:, type:, collection: false)
          @rules << YamlsSequenceRule.new(position, to: to, type: type,
                                                    collection: collection)
        end
      end
    end
  end
end
