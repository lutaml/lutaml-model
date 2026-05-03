module Lutaml
  module Model
    module Services
      class Base
        # rubocop:disable Style/ArgumentsForwarding -- anonymous * requires Ruby 3.2+
        def self.call(*args)
          new(*args).call
          # rubocop:enable Style/ArgumentsForwarding
        end
      end
    end
  end
end
