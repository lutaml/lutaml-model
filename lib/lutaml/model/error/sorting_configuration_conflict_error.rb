module Lutaml
  module Model
    class SortingConfigurationConflictError < Error
      def to_s
        "Keeping the order of input (ordered: true) and sorting (sort by <element name>) are not supported together, Please choose one or the other."
      end
    end
  end
end
