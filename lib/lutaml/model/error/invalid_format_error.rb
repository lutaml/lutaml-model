# frozen_string_literal: true

module Lutaml
  module Model
    class InvalidFormatError < Error
      def initialize(allowed_format, message = nil)
        super("input format is invalid, try to pass correct `#{allowed_format}` format \n#{message}\n\n")
      end
    end
  end
end
