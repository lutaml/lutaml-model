module Lutaml
  module Model
    class LiquidNotEnabledError < Error
      def to_s
        "Liquid functionality is not available by default; please install and require `liquid` gem to use this functionality"
      end
    end
  end
end
