# frozen_string_literal: true

require "thor"
require "lutaml/model"

module Lutaml
  module Model
    class Cli < Thor
      # Compare two files using a Lutaml::Model model.
      # Outputs a similarity score and a detailed diff for comparison.
      #
      # Example:
      #   lutaml-model compare file1.xml file2.xml -m model.rb -r RootClass
      desc "compare PATH_1 PATH_2", "Compare two files using a Lutaml::Model model. Outputs similarity and differences. Supports XML, YAML, JSON, and more."
      option :model_file, aliases: "-m", type: :string, default: nil, desc: "Path to the Ruby file defining your Lutaml::Model classes (required)"
      option :root_class, aliases: "-r", type: :string, default: nil, desc: "Name of the root model class to use for parsing (required)"
      def compare(path1, path2)
        raise ArgumentError, "File not found: #{path1}" unless File.file?(path1)
        raise ArgumentError, "File not found: #{path2}" unless File.file?(path2)

        validate_compare_options!(options)

        require File.expand_path(options[:model_file])
        model_class = constantize_model!(options[:root_class])

        compare_files!(path1, path2, model_class)
      end

      private

      def compare_files!(path1, path2, model_class)
        record1 = model_from_file(path1, model_class)
        record2 = model_from_file(path2, model_class)

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
      end

      def model_from_file(path, model)
        content = File.read(path)
        format = path.split(".").last.downcase
        format = "yaml" if format == "yml"

        model.send("from_#{format}", content)
      rescue StandardError => e
        raise StandardError, "Error parsing file #{path}: #{e.message}"
      end

      def constantize_model!(model_name)
        Object.const_get(model_name)
      rescue NameError
        raise NameError, "#{model_name} not defined in model-file"
      end
    end
  end
end
