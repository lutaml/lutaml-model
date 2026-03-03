# frozen_string_literal: true

require "pathname"
require "ripper"
require "yaml"

module CodeExampleValidator
  # Represents a single code example extracted from documentation
  class Example
    attr_reader :file, :line_number, :code, :context, :type

    def initialize(file:, line_number:, code:, context: nil, type: :snippet)
      @file = file
      @line_number = line_number
      @code = code
      @context = context
      @type = type # :complete or :snippet
    end

    def identifier
      "#{file}:#{line_number}"
    end

    def complete?
      type == :complete
    end

    def snippet?
      type == :snippet
    end

    # Check if the code appears to be a complete program
    def looks_complete?
      return false if code.strip.empty?

      has_require = code.include?("require")
      has_class_or_module = code =~ /^(class|module)\s+\w+/
      has_method_definition = code =~ /^def\s+\w+/
      has_executable_code = !code.strip.start_with?("#")

      # Complete if it has requires and class/module definitions
      # or if it has method definitions with requires
      (has_require && (has_class_or_module || has_method_definition)) ||
        (has_require && has_executable_code && code.lines.count > 5)
    end

    def syntax_valid?
      !Ripper.sexp(code).nil?
    rescue StandardError
      false
    end

    def has_requires?
      code.match?(/require\s+['"]/)
    end

    def requires_lutaml_xsd?
      code.match?(%r{require\s+['"]lutaml[/-]xsd})
    end

    def to_h
      {
        file: file,
        line_number: line_number,
        identifier: identifier,
        type: type,
        context: context,
        code_length: code.lines.count,
        has_requires: has_requires?,
        requires_lutaml_xsd: requires_lutaml_xsd?,
        looks_complete: looks_complete?,
        syntax_valid: syntax_valid?,
      }
    end
  end

  # Extracts code examples from AsciiDoc files
  class Extractor
    RUBY_CODE_BLOCK_START = [
      /^\[source,ruby\]$/, # AsciiDoc style
      /^```ruby$/, # Markdown style
    ].freeze

    BLOCK_DELIMITER_START = /^----$/

    BLOCK_END_PATTERNS = [
      /^----$/,
      /^```$/,
    ].freeze

    attr_reader :root_dir

    def initialize(root_dir)
      @root_dir = Pathname.new(root_dir)
    end

    def extract_from_file(file_path)
      examples = []
      lines = File.readlines(file_path)
      in_code_block = false
      waiting_for_delimiter = false
      code_lines = []
      start_line = 0
      context = nil

      lines.each_with_index do |line, idx|
        if !in_code_block && !waiting_for_delimiter && ruby_code_block_start?(line)
          # Found [source,ruby] or ```ruby
          waiting_for_delimiter = true
          start_line = idx + 1
          context = extract_context(lines, idx)
        elsif waiting_for_delimiter && (block_delimiter_start?(line) || line.strip.empty?)
          # Found ---- or empty line after [source,ruby]
          if block_delimiter_start?(line)
            in_code_block = true
            waiting_for_delimiter = false
            code_lines = []
          end
          # Skip empty lines between [source,ruby] and ----
        elsif !in_code_block && !waiting_for_delimiter
          # Normal line, do nothing
        elsif in_code_block && code_block_end?(line)
          in_code_block = false
          unless code_lines.empty?
            code = code_lines.join
            type = determine_type(code)
            examples << Example.new(
              file: relative_path(file_path),
              line_number: start_line + 1,
              code: code,
              context: context,
              type: type,
            )
          end
          code_lines = []
        elsif in_code_block
          code_lines << line
        end
      end

      examples
    end

    def extract_all(pattern: "**/*.adoc")
      examples = []
      Dir.glob(root_dir.join(pattern)).each do |file|
        examples.concat(extract_from_file(file))
      end
      examples
    end

    private

    def ruby_code_block_start?(line)
      RUBY_CODE_BLOCK_START.any? { |pattern| line.strip.match?(pattern) }
    end

    def block_delimiter_start?(line)
      line.strip.match?(BLOCK_DELIMITER_START)
    end

    def code_block_end?(line)
      BLOCK_END_PATTERNS.any? { |pattern| line.match?(pattern) }
    end

    def relative_path(file_path)
      Pathname.new(file_path).relative_path_from(root_dir).to_s
    end

    def extract_context(lines, current_idx)
      # Look back up to 10 lines for a heading or description
      context_lines = []
      (1..10).each do |offset|
        break if current_idx - offset < 0

        line = lines[current_idx - offset]
        # AsciiDoc heading
        if line.match?(/^=+\s+/)
          context_lines.unshift(line.strip)
          break
        # Example block marker
        elsif line.match?(/^====/)
          # Continue looking for heading
          next
        elsif line.match?(/^\[example\]/)
          # Continue looking for heading
          next
        elsif line.strip.empty?
          # Skip empty lines
          next
        elsif line.match?(/^\./)
          # Block title
          context_lines.unshift(line.strip)
        end
      end

      context_lines.empty? ? nil : context_lines.join(" / ")
    end

    def determine_type(code)
      # Heuristics to determine if code is complete or snippet
      has_require = code.include?("require")
      has_class = code.match?(/^(class|module)\s+\w+/)
      has_instantiation = code.match?(/\w+\.new/)
      lines = code.lines.count

      if has_require && (has_class || (has_instantiation && lines > 10))
        :complete
      else
        :snippet
      end
    end
  end

  # Validates extracted code examples
  class Validator
    attr_reader :examples, :results

    def initialize(examples)
      @examples = examples
      @results = {
        total: 0,
        complete: 0,
        snippets: 0,
        syntax_valid: 0,
        syntax_invalid: 0,
        has_requires: 0,
        requires_lutaml: 0,
        by_file: {},
        failures: [],
      }
    end

    def validate_all
      @results[:total] = examples.count

      examples.each do |example|
        validate_example(example)
      end

      @results
    end

    def validate_example(example)
      file = example.file
      @results[:by_file][file] ||= {
        total: 0,
        complete: 0,
        snippets: 0,
        syntax_valid: 0,
        syntax_invalid: 0,
      }

      @results[:by_file][file][:total] += 1

      # Count by type
      if example.complete?
        @results[:complete] += 1
        @results[:by_file][file][:complete] += 1
      else
        @results[:snippets] += 1
        @results[:by_file][file][:snippets] += 1
      end

      # Count requires
      @results[:has_requires] += 1 if example.has_requires?
      @results[:requires_lutaml] += 1 if example.requires_lutaml_xsd?

      # Validate syntax
      if example.syntax_valid?
        @results[:syntax_valid] += 1
        @results[:by_file][file][:syntax_valid] += 1
      else
        @results[:syntax_invalid] += 1
        @results[:by_file][file][:syntax_invalid] += 1
        @results[:failures] << {
          identifier: example.identifier,
          type: :syntax_error,
          context: example.context,
        }
      end
    end

    def summary
      <<~SUMMARY
        Code Example Validation Summary
        ================================

        Total Examples: #{@results[:total]}
        - Complete Programs: #{@results[:complete]}
        - Code Snippets: #{@results[:snippets]}

        Syntax Validation:
        - Valid: #{@results[:syntax_valid]} (#{percentage(@results[:syntax_valid], @results[:total])}%)
        - Invalid: #{@results[:syntax_invalid]} (#{percentage(@results[:syntax_invalid], @results[:total])}%)

        Dependencies:
        - Examples with requires: #{@results[:has_requires]}
        - Examples requiring lutaml-xsd: #{@results[:requires_lutaml]}

        Failures: #{@results[:failures].count}
      SUMMARY
    end

    def detailed_report
      report = [summary]
      report << "\nBy File:\n"
      report << ("=" * 80)

      @results[:by_file].sort.each do |file, stats|
        report << "\n#{file}:"
        report << "  Total: #{stats[:total]}"
        report << "  Complete: #{stats[:complete]}, Snippets: #{stats[:snippets]}"
        report << "  Syntax Valid: #{stats[:syntax_valid]}, Invalid: #{stats[:syntax_invalid]}"
      end

      if @results[:failures].any?
        report << "\n\nFailures:\n"
        report << ("=" * 80)
        @results[:failures].each do |failure|
          report << "\n#{failure[:identifier]}"
          report << "  Type: #{failure[:type]}"
          report << "  Context: #{failure[:context]}" if failure[:context]
        end
      end

      report.join("\n")
    end

    private

    def percentage(count, total)
      return 0 if total.zero?

      ((count.to_f / total) * 100).round(1)
    end
  end

  # Generates reports
  class Reporter
    def self.generate_markdown(validator:, examples:)
      report = []
      report << "# Code Examples Validation Report"
      report << ""
      report << "Generated: #{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}"
      report << ""
      report << "## Summary"
      report << ""
      report << validator.summary
      report << ""
      report << "## Examples by File"
      report << ""

      validator.results[:by_file].sort.each do |file, stats|
        report << "### #{file}"
        report << ""
        report << "| Metric | Count |"
        report << "|--------|-------|"
        report << "| Total Examples | #{stats[:total]} |"
        report << "| Complete Programs | #{stats[:complete]} |"
        report << "| Code Snippets | #{stats[:snippets]} |"
        report << "| Syntax Valid | #{stats[:syntax_valid]} |"
        report << "| Syntax Invalid | #{stats[:syntax_invalid]} |"
        report << ""
      end

      if validator.results[:failures].any?
        report << "## Failures"
        report << ""
        validator.results[:failures].each do |failure|
          report << "- **#{failure[:identifier]}**"
          report << "  - Type: #{failure[:type]}"
          report << "  - Context: #{failure[:context]}" if failure[:context]
          report << ""
        end
      end

      report << "## Recommendations"
      report << ""
      report << "1. Fix all syntax errors in code examples"
      report << "2. Ensure all complete examples can run independently"
      report << "3. Add missing `require` statements to complete examples"
      report << "4. Consider adding comments to clarify snippet context"
      report << ""

      report.join("\n")
    end

    def self.generate_yaml(examples:)
      examples.map(&:to_h).to_yaml
    end
  end
end
