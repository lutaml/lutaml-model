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
      %w(String
         Integer
         Float
         Date
         Time
         Boolean
         Decimal
         Hash
         UUID
         Symbol
         BigInteger
         Binary
         URL
         Email
         IPAddress
         JSON
         Enum).each do |t|
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

      class TimeWithoutDate
        def self.cast(value)
          return if value.nil?

          ::Time.parse(value.to_s)
          # .strftime("%H:%M:%S")
        end

        def self.serialize(value)
          value.strftime("%H:%M:%S")
        end
      end

      class DateTime
        def self.cast(value)
          return if value.nil?

          ::DateTime.parse(value.to_s).new_offset(0)
        end

        def self.serialize(value)
          value.iso8601
        end
      end

      class Array
        def initialize(array)
          Array(array)
        end
      end

      class TextWithTags
        attr_reader :content

        def initialize(ordered_text_with_tags)
          @content = ordered_text_with_tags
        end

        def self.cast(value)
          return value if value.is_a?(self)

          new(value)
        end

        def self.serialize(value)
          value.content.join
        end
      end

      class JSON
        attr_reader :value

        def initialize(value)
          @value = value
        end

        def to_json(*_args)
          @value.to_json
        end

        def ==(other)
          @value == if other.is_a?(::Hash)
                      other
                    else
                      other.value
                    end
        end

        def self.cast(value)
          return value if value.is_a?(self) || value.nil?

          new(::JSON.parse(value))
        end

        def self.serialize(value)
          value.to_json
        end
      end

      UUID_REGEX = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

      def self.cast(value, type)
        return if value.nil?

        if [String, Email].include?(type)
          value.to_s
        elsif [Integer, BigInteger].include?(type)
          value.to_i
        elsif type == Float
          value.to_f
        elsif type == Date
          begin
            ::Date.parse(value.to_s)
          rescue ArgumentError
            nil
          end
        elsif type == DateTime
          DateTime.cast(value)
        elsif type == Time
          ::Time.parse(value.to_s)
        elsif type == TimeWithoutDate
          TimeWithoutDate.cast(value)
        elsif type == Boolean
          to_boolean(value)
        elsif type == Decimal
          BigDecimal(value.to_s)
        elsif type == Hash
          normalize_hash(Hash(value))
        elsif type == UUID
          UUID_REGEX.match?(value) ? value : SecureRandom.uuid
        elsif type == Symbol
          value.to_sym
        elsif type == Binary
          value.force_encoding("BINARY")
        elsif type == URL
          URI.parse(value.to_s)
        elsif type == IPAddress
          IPAddr.new(value.to_s)
        elsif type == JSON
          JSON.cast(value)
        # elsif type == Enum
        #   value
        else
          value
        end
      end

      def self.serialize(value, type)
        return if value.nil?

        if type == Date
          value.iso8601
        elsif type == DateTime
          DateTime.serialize(value)
        elsif type == Integer
          value.to_i
        elsif type == Float
          value.to_f
        elsif type == Boolean
          to_boolean(value)
        elsif type == Decimal
          value.to_s("F")
        elsif type == Hash
          Hash(value)
        elsif type == JSON
          value.to_json
        else
          value.to_s
        end
      end

      def self.to_boolean(value)
        return true if value == true || value.to_s =~ (/^(true|t|yes|y|1)$/i)
        return false if value == false || value.nil? || value.to_s =~ (/^(false|f|no|n|0)$/i)

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
