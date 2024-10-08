module Lutaml
  module Model
    module Type
      # Time representation without date
      class TimeWithoutDate
        def self.cast(value)
          return if value.nil?

          ::Time.parse(value.to_s)
        end

        def self.serialize(value)
          value.strftime("%H:%M:%S")
        end
      end
    end
  end
end
