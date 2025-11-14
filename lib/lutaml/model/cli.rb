# frozen_string_literal: true

require "thor"
require "lutaml/model"

module Lutaml
  module Model
    class Cli < Thor
      # lutaml-model compare "path_to_file_1" "path_to_file_2" --root-class RootClassName --format xml --model-file path_to_model_file
      desc "compare PATH_1 PATH_2", "Detect duplicate records readable by Lutaml::Model, files or directories"
      option :model_file, type: :string, default: nil, desc: "Path to the model file"
      option :root_class, type: :string, default: nil, desc: "Root class name"
      option :format, type: :string, default: nil, desc: "Format of the input files"
      def compare(path1, path2)
        raise ArgumentError, "File not found: #{path1}" unless File.file?(path1)
        raise ArgumentError, "File not found: #{path2}" unless File.file?(path2)

        validate_compare_options!(options)

        require options[:model_file]

        format = options[:format]
        model_class = Object.const_get(options[:root_class])
        record1 = model_from_file(path1, model_class, format)
        record2 = model_from_file(path2, model_class, format)

        diff_score, diff_tree = Lutaml::Model::Serialize.diff_with_score(
          record1,
          record2,
          show_unchanged: false,
          highlight_diff: false,
          use_colors: true,
          indent: "  ",
        )
        similarity_percentage = (1 - diff_score) * 100

        puts "Differences between #{path1} and #{path2}:"
        puts diff_tree
        puts "Similarity score: #{similarity_percentage.round(2)}%"
      end

      def validate_compare_options!(options)
        raise ArgumentError, "model_file argument is required" unless options[:model_file]
        raise ArgumentError, "Model file not found: #{options[:model_file]}" unless File.file?(options[:model_file])
        raise ArgumentError, "root_class argument is required" unless options[:root_class]
        raise ArgumentError, "format argument is required" unless options[:format]
      end

      def model_from_file(path, model, format)
        content = File.read(path)

        model.send("from_#{format}", content)
      rescue StandardError => e
        raise StandardError, "Error parsing file #{path}: #{e.message}"
      end
    end
  end
end
