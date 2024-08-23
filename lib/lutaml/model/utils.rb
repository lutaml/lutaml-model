# frozen_string_literal: true

module Lutaml
  module Model
    module Utils

      # Convert string to camel case
      def self.camel_case(str)
        return '' if str.nil? || str.empty?
        str[0].upcase + str[1..-1]
      end

      # Convert string to class name
      def self.classify(str)
        str = str.to_s.gsub('.', '')

        str = str.sub(/^[a-z\d]*/) { |match| camel_case(match) || match }

        str.gsub('::', '/').gsub(%r{(?:_|-|(/))([a-z\d]*)}i) do
          word = Regexp.last_match(2)
          substituted = camel_case(word) || word
          Regexp.last_match(1) ? "::#{substituted}" : substituted
        end
      end

      # Convert string to snake case
      def self.snake_case(str)
        # XML elements allow periods and hyphens
        str = str.to_s.gsub('.', '_')
        return str.to_s unless /[A-Z-]|::/.match?(str)
        word = str.to_s.gsub('::', '/')
        word = word.gsub(/([A-Z]+)(?=[A-Z][a-z])|([a-z\d])(?=[A-Z])/) do
          "#{Regexp.last_match(1) || Regexp.last_match(2)}_"
        end
        word = word.tr('-', '_')
        word.downcase
      end

      # Convert word to under score
      def self.underscore(str)
        snake_case(str).split('/').last
      end
    end
  end
end