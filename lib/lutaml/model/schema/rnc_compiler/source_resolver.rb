# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RncCompiler
        # Resolves RNC input text and the base directory used for relative
        # include paths.
        class SourceResolver
          ResolvedSource =
            Struct.new(:text, :base_dir, :path, keyword_init: true)

          def initialize(input, options)
            @input = input
            @location = options[:location].to_s
          end

          def resolve
            return file_source if !location.empty? && File.file?(location)

            ResolvedSource.new(
              text: input.to_s,
              base_dir: directory_location,
            )
          end

          private

          attr_reader :input, :location

          def file_source
            path = File.expand_path(location)
            raise "RNC schema file not found: #{path}" unless File.file?(path)

            ResolvedSource.new(
              text: File.read(path),
              base_dir: File.dirname(path),
              path: path,
            )
          end

          def directory_location
            return if location.empty?
            return unless File.directory?(location)

            File.expand_path(location)
          end
        end
      end
    end
  end
end
