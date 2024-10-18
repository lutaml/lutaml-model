module Lutaml
  module Model
    module Group
      class KeyValue
        attr_reader :dict,
                    :method_from,
                    :method_to

        def initialize(method_from, method_to)
          @method_from = method_from
          @method_to = method_to
          @dict = {}
        end

        def add(key, value)
          @dict[key] = value
        end
      end
    end
  end
end
