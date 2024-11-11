module Lutaml
  module Model
    module Type
      class Date < Value
        def self.cast(value)
          return nil if value.nil?

          case value
          when ::Date
            value
          when ::DateTime, ::Time
            value.to_date
          else
            ::Date.parse(value.to_s)
          end
        rescue ArgumentError
          nil
        end

        # xs:date format
        def self.serialize(value)
          return nil if value.nil?

          value&.iso8601
        end
      end
    end
  end
end
