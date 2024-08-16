require "date"
require "bigdecimal"
require "securerandom"
require "uri"
require "ipaddr"

module Lutaml
  module Model
    module Type
      # This module provides a set of methods to cast and serialize values

      # TODO: Make Boolean a separate class

      %w(
        String
        Integer
        Float
        Date
        Time
        Boolean
        Decimal
        Hash
        Uuid
        Symbol
        Binary
        Url
        IpAddress
        Json
      ).each do |t|
        class_eval <<~HEREDOC, __FILE__, __LINE__ + 1
                     class #{t}                        # class Integer
            def self.cast(value)            #   def self.cast(value)
              return if value.nil?          #     return if value.nil?
              Type.cast(value, #{t})        #     Type.cast(value, Integer)
            end                             #   end

            def self.serialize(value)       #   def self.serialize(value)
              return if value.nil?          #     return if value.nil?
              Type.serialize(value, #{t})   #     Type.serialize(value, Integer)
            end                             #   end
          end                               # end
        HEREDOC
      end

      UUID_REGEX = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

      def self.cast(value, type)
        return if value.nil?

        case type.to_s.split("::").last
        when "String"
          value.to_s
        when "Integer"
          value.to_i
        when "Float"
          value.to_f
        when "Date"
          begin
            ::Date.parse(value.to_s)
          rescue ArgumentError
            nil
          end
        when "DateTime"
          DateTime.cast(value)
        when "Time"
          ::Time.parse(value.to_s)
        when "TimeWithoutDate"
          TimeWithoutDate.cast(value)
        when "Boolean"
          to_boolean(value)
        when "Decimal"
          BigDecimal(value.to_s)
        when "Hash"
          normalize_hash(Hash(value))
        when "Uuid"
          UUID_REGEX.match?(value) ? value : SecureRandom.uuid
        when "Symbol"
          value.to_sym
        when "Binary"
          value.force_encoding("BINARY")
        when "Url"
          URI.parse(value.to_s)
        when "IpAddress"
          IPAddr.new(value.to_s)
        when "Json"
          Json.cast(value)
        else
          value
        end
      end

      def self.serialize(value, type)
        return if value.nil?

        case type.to_s.split("::").last
        when "Date"
          value.iso8601
        when "DateTime"
          DateTime.serialize(value)
        when "Integer"
          value.to_i
        when "Float"
          value.to_f
        when "Boolean"
          to_boolean(value)
        when "Decimal"
          value.to_s("F")
        when "Hash"
          Hash(value)
        when "Json"
          value.to_json
        else
          value.to_s
        end
      end

      def self.to_boolean(value)
        if value == true || value.to_s =~ (/^(true|t|yes|y|1)$/i)
          return true
        end

        if value == false || value.nil? || value.to_s =~ (/^(false|f|no|n|0)$/i)
          return false
        end

        raise ArgumentError.new("invalid value for Boolean: \"#{value}\"")
      end

      def self.normalize_hash(hash)
        return hash["text"] if hash.keys == ["text"]

        hash.filter_map do |key, value|
          next if key == "text"

          if value.is_a?(::Hash)
            [key, normalize_hash(value)]
          else
            [key, value]
          end
        end.to_h
      end
    end
  end
end

require_relative "type/time_without_date"
require_relative "type/date_time"
require_relative "type/json"
