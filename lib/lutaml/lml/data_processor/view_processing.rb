# frozen_string_literal: true

module Lutaml
  module Lml
    class DataProcessor
      module ViewProcessing
        # entity_name_list parses to a Hash (one name) or an Array of
        # Hashes (several); normalize both to one list of strings.
        def process_show_list(data)
          entity_names_from(data)
        end

        def process_hide_list(data)
          entity_names_from(data)
        end

        private

        def entity_names_from(data)
          entries = data.is_a?(Array) ? data : [data]
          entries.map { |entry| entry[:entity_name].to_s }
        end
      end
    end
  end
end
