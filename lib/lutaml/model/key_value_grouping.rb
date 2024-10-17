require_relative "key_value"

module Lutaml
  module Model
    module Group
      class KeyValueGrouping
        def initialize
          @groups = {}
        end

        def add(mapping, value)
          group = @groups[mapping.group] ||= KeyValue.new(mapping.method_from, mapping.method_to)
          group.add(mapping.name, value)
        end

        def each(&block)
          @groups.values.each(&block)
        end
      end
    end
  end
end
