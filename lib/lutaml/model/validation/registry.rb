# frozen_string_literal: true

module Lutaml
  module Model
    module Validation
      class Registry
        def initialize
          @rules = []
          @mutex = Mutex.new
        end

        def register(rule_class)
          @mutex.synchronize do
            @rules << rule_class unless @rules.include?(rule_class)
          end
        end

        def auto_discover(dir, pattern: "**/*_rule.rb")
          Dir.glob(File.join(dir, pattern)).each do |path|
            require path
          end
        end

        def all
          @rules.map(&:new)
        end

        def for_category(category)
          all.select { |r| r.category == category }
        end

        def find(code)
          all.find { |r| r.code == code }
        end

        def reset!
          @mutex.synchronize { @rules.clear }
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
