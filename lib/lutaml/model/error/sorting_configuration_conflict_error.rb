module Lutaml
  module Model
    class SortingConfigurationConflictError < Error
      def to_s
        "Invalid sorting configuration: cannot combine outer sort (sort by ...) with inner element sort (ordered: true in XML mapping`). Please choose one."
      end
    end
  end
end
