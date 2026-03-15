module Lutaml
  module Model
    module Services
      class Base
        def self.call(*)
          new(*).call
        end
      end
    end
  end
end
