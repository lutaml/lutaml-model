module Lutaml
  module Model
    module Type
      class Date < Value
        def self.cast(value)
          return if value.nil?
          ::Date.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def self.serialize(value)
          value&.iso8601
        end
      end

      register(:date, Lutaml::Model::Type::Date)
    end
  end
end
