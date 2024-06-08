# lib/lutaml/model/type.rb
require "date"
require "bigdecimal"
require "securerandom"
require "uri"
require "ipaddr"
require "json"

module Lutaml
  module Model
    module Type
      String = "String"
      Integer = "Integer"
      Float = "Float"
      Date = "Date"
      # DateTime = "DateTime"
      Time = "Time"
      # TimeWithoutDate = "TimeWithoutDate"
      Boolean = "Boolean"
      Decimal = "Decimal"
      Array = "Array"
      Hash = "Hash"
      UUID = "UUID"
      Symbol = "Symbol"
      BigInteger = "BigInteger"
      Binary = "Binary"
      URL = "URL"
      Email = "Email"
      IPAddress = "IPAddress"
      JSON = "JSON"
      Enum = "Enum"

      class TimeWithoutDate
        def self.cast(value)
          parsed_time = ::Time.parse(value.to_s)
          parsed_time.strftime("%H:%M:%S")
        end

        def self.serialize(value)
          value.strftime("%H:%M:%S")
        end
      end

      class DateTime
        def self.cast(value)
          ::DateTime.parse(value.to_s).new_offset(0).iso8601
        end
      end

      def self.cast(value, type)
        case type
        when String
          value.to_s
        when Integer
          value.to_i
        when Float
          value.to_f
        when Date
          begin
            ::Date.parse(value.to_s)
          rescue ArgumentError
            nil
          end
        when DateTime
          DateTime.cast(value)
        when Time
          ::Time.parse(value.to_s)
        when TimeWithoutDate
          TimeWithoutDate.cast(value)
        when Boolean
          to_boolean(value)
        when Decimal
          BigDecimal(value.to_s)
        when Array
          Array(value)
        when Hash
          Hash(value)
        when UUID
          value =~ /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/ ? value : SecureRandom.uuid
        when Symbol
          value.to_sym
        when BigInteger
          value.to_i
        when Binary
          value.force_encoding("BINARY")
        when URL
          URI.parse(value.to_s)
        when Email
          value.to_s
        when IPAddress
          IPAddr.new(value.to_s)
        when JSON
          ::JSON.parse(value)
        when Enum
          value
        else
          value
        end
      end

      def self.to_boolean(value)
        return true if value == true || value.to_s =~ (/^(true|t|yes|y|1)$/i)
        return false if value == false || value.nil? || value.to_s =~ (/^(false|f|no|n|0)$/i)
        raise ArgumentError.new("invalid value for Boolean: \"#{value}\"")
      end
    end
  end
end
