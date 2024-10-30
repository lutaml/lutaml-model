require "time"

module Lutaml
  module Model
    module Type
      class TimeWithoutDate < Value
        def self.cast(value)
          return nil if value.nil?
          time = ::Time.parse(value.to_s)
          ::Time.new(1, 1, 1, time.hour, time.min, time.sec)
        rescue ArgumentError
          nil
        end

        def self.serialize(value)
          return nil if value.nil?
          value.strftime("%H:%M:%S")
        end
      end

      register(:time_without_date, TimeWithoutDate)
    end
  end
end
