require "time"

module Lutaml
  module Model
    module Type
      class TimeWithoutDate < Value
        def self.cast(value)
          return nil if value.nil?

          ::Time.parse(value.to_s)

          # TODO: we probably want to do something like this because using
          # Time.parse will set the date to today.
          #
          # time = ::Time.parse(value.to_s)
          # ::Time.new(1, 1, 1, time.hour, time.min, time.sec)
        rescue ArgumentError
          nil
        end

        def self.serialize(value)
          return nil if value.nil?

          value.strftime("%H:%M:%S")
        end
      end

      register(:time_without_date, Lutaml::Model::Type::TimeWithoutDate)
    end
  end
end
