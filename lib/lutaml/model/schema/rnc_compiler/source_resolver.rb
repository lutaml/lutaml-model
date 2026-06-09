# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RncCompiler
        # Resolves RNC input text and the base directory used for relative
        # include paths.
        module SourceResolver
          ResolvedSource =
            Struct.new(:text, :base_dir, :path, keyword_init: true)

          module_function

          def resolve(input, options)
            location = options[:location].to_s
            return string_source(input) if location.empty?

            expanded = File.expand_path(location)
            if File.file?(expanded)
              return file_source(expanded) if input.nil? || input.to_s.empty?

              return string_source(input, base_dir: File.dirname(expanded), path: expanded)
            end
            return string_source(input, base_dir: expanded) if File.directory?(expanded)

            string_source(input)
          end

          def string_source(input, base_dir: nil, path: nil)
            ResolvedSource.new(text: input.to_s, base_dir: base_dir, path: path)
          end

          def file_source(path)
            ResolvedSource.new(
              text: File.read(path),
              base_dir: File.dirname(path),
              path: path,
            )
          end

          private_class_method :string_source, :file_source
        end
      end
    end
  end
end
