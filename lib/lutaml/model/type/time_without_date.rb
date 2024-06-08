# lib/lutaml/model/type/time_without_date.rb
module Lutaml
  module Model
    module Type
      class TimeWithoutDate
        def self.cast(value)
          parsed_time = ::Time.parse(value.to_s)
          parsed_time.strftime("%H:%M:%S")
        end

        def self.serialize(value)
          value.strftime("%H:%M:%S")
        end
      end
    end
  end
end
