# frozen_string_literal: true

module Lutaml
  module Model
    module Validation
      # Instance-based rule registry. Register rule classes, look up by
      # code or category, and instantiate all registered rules for
      # validation runs.
      class Registry
        def initialize
          @rules = []
          @mutex = Mutex.new
          @all = nil
        end

        def register(rule_class)
          @mutex.synchronize do
            return if @rules.include?(rule_class)

            @rules << rule_class
            @all = nil
          end
        end

        def auto_discover(dir, pattern: "**/*_rule.rb")
          Dir.glob(File.join(dir, pattern)).each { |path| require path }
        end

        def all
          @mutex.synchronize do
            @all ||= @rules.map(&:new)
          end
        end

        def for_category(category)
          all.select { |r| r.category == category }
        end

        def find(code)
          all.find { |r| r.code == code }
        end

        def reset!
          @mutex.synchronize do
            @rules.clear
            @all = nil
          end
        end

        def rule_classes
          @rules.dup
        end

        def size
          @rules.size
        end
      end
    end
  end
end
