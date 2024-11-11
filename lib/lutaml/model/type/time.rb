require "time"

module Lutaml
  module Model
    module Type
      class Time < Value
        def self.cast(value)
          return if value.nil?

          ::Time.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def self.serialize(value)
          return nil if value.nil?

          value&.iso8601
        end
      end

      register(:time, Lutaml::Model::Type::Time)
    end
  end
end
