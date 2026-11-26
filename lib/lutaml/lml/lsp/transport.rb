# frozen_string_literal: true

require "json"

module Lutaml
  module Lml
    module Lsp
      # LSP base protocol framing: `Content-Length: N\r\n\r\n<json>`.
      # Reads one message at a time and writes responses to the output
      # stream. stdout is the protocol channel; stderr is for logging.
      class Transport
        def initialize(input: $stdin, output: $stdout)
          @input = input
          @output = output
        end

        def read_message
          headers = read_headers
          return nil unless headers

          length = headers["content-length"]
          return nil unless length

          body = @input.read(length.to_i)
          body.nil? || body.empty? ? nil : JSON.parse(body)
        end

        def write_message(payload)
          body = JSON.generate(payload)
          @output.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}")
          @output.flush
        end

        private

        def read_headers
          headers = {}
          loop do
            line = @input.gets
            return nil if line.nil?

            line = line.chomp
            break if line.empty?

            key, value = line.split(":", 2)
            headers[key.to_s.strip.downcase] = value.to_s.strip
          end
          headers
        end
      end
    end
  end
end
