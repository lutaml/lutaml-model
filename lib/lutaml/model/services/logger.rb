module Lutaml
  module Model
    class Logger
      def self.warn(message)
        new.call(message, :warn)
      end

      # @param [String] old: The name of the deprecated class or method
      # @param [String] replacement: The name of the replacement class or method
      #
      # Outputs a warning message that
      #   Usage of `old` name is deprecated will be removed in the next major
      #   release. Please use the `replacement`` instead.
      def self.warn_future_deprecation(old:, replacement:)
        warn("Usage of `#{old}` is deprecated and will be removed in the next major release. Please use `#{replacement}` instead.")
      end

      # @param [String] name
      # @param [String] caller_file
      # @param [Integer] caller_line
      #
      # Outputs a warning message that
      #   `<name>` is handled by default. No need to explicitly
      #   define at `<caller_file>:<caller_line>`.
      def self.warn_auto_handling(name:, caller_file:, caller_line:)
        warn("`#{name}` is handled by default. No need to explicitly define at `#{caller_file}:#{caller_line}`")
      end

      def call(message, type)
        Warning.warn format_message(message, type)
      end

      private

      def colorize(message, type)
        type_color = {
          error: 31, # Red: 31
          success: 32, # Green: 32
          warn: 33, # Yellow: 33
        }

        io = type == :warn ? $stderr : $stdout
        return message unless io.tty?

        color = type_color[type]
        "\e[#{color}m#{message}\e[0m"
      end

      def format_message(message, type)
        colorize("\n[Lutaml::Model] #{type.upcase}: #{message}\n", type)
      end
    end
  end
end
