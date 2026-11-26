# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      # Caller-owned declarations for trusted named scalar classes. This is
      # data, not an inference about Ruby callbacks or an executable binding.
      class ValueDeclarations
        VERSION = 1
        NUMERIC_BASES = %w[integer decimal positive_integer non_negative_integer].freeze
        BOUND_FACETS = %w[min_inclusive max_inclusive min_exclusive max_exclusive].freeze
        COUNT_FACETS = %w[length min_length max_length total_digits fraction_digits].freeze
        WHITE_SPACE = %w[preserve replace collapse].freeze
        ORDERED_FACETS = [%w[min_length max_length], %w[fraction_digits total_digits]].freeze
        DECIMAL_TEXT = /\A-?\d+(?:\.\d+)?\z/
        attr_reader :version

        def initialize(entries, version: VERSION)
          unless version.is_a?(::Integer) && version == VERSION
            raise RejectedError.new(:unsupported_version, nil, "unsupported named-value declaration registry version")
          end
          unless entries.is_a?(::Hash)
            raise RejectedError.new(:invalid_document, nil, "named-value declarations require a class-keyed Hash")
          end

          @version = version
          @entries = entries.each_with_object({}) do |(klass, definition), out|
            unless klass.is_a?(::Class) && klass < Lutaml::Model::Type::Value && klass.name && !klass.name.empty?
              raise RejectedError.new(:unsupported_type, nil, "named-value declaration keys must be named scalar classes")
            end
            if builtin_classes.include?(klass)
              raise RejectedError.new(:unsupported_type, klass.name,
                                      "#{klass} is a builtin type; it is not a custom named value")
            end

            spec = data_copy(definition)
            tree = DocumentValidator.validate!({
                                                 "lml_bundle" => 1, "roots" => [], "models" => {},
                                                 "value_types" => { "#{klass.name}@default" => spec }, "capabilities" => []
                                               }, kind: :bundle)
            declaration = tree.fetch("value_types").fetch("#{klass.name}@default")
            check_facets!(klass, declaration.fetch("facets"))
            out[klass] = freeze_tree(declaration)
          end.freeze
          freeze
        end

        # Class identity is exact: names, aliases, subclasses and strings never
        # gain a declaration merely because their spelling resembles a key.
        def fetch(klass)
          @entries[klass]
        end

        # Why +json+ (a default already shaped for the declared base) breaks a
        # declared facet of +klass+, or nil. Bounds and digit counts apply to
        # numeric bases (exact decimal text) and bounds to float wire text;
        # length and pattern to string-shaped bases.
        def facet_violation(klass, json)
          declaration = @entries[klass]
          return nil unless declaration

          base = declaration["base"]
          declaration.fetch("facets", {}).each do |name, limit|
            problem = if NUMERIC_BASES.include?(base) then numeric_problem(name, limit, json)
                      elsif base == "float" && BOUND_FACETS.include?(name) then float_bound_problem(name, limit, json)
                      else text_problem(name, limit, json)
                      end
            return problem if problem
          end
          nil
        end

        def to_h
          { "version" => version,
            "types" => @entries.sort_by { |klass, _| klass.name }.to_h { |klass, spec| [klass.name, spec] } }
        end

        private

        # The facets the exporter checks defaults against must be well formed,
        # and bounds consistent, when the declaration is made. Any other facet
        # name is carried as caller-owned data.
        def check_facets!(klass, facets)
          checked = facets.each { |name, value| facet_value!(klass, name, value) }
          ORDERED_FACETS.each do |low, high|
            next unless checked.key?(low) && checked.key?(high) && checked[low] > checked[high]

            raise RejectedError.new(:invalid_document, klass.name, "#{klass}: #{low} exceeds #{high}")
          end
        end

        def facet_value!(klass, name, value)
          ok = if COUNT_FACETS.include?(name) then safe_integer?(value) && value >= 0
               elsif name == "pattern" then value.is_a?(::String) && !value.empty? && DocumentValidator.portable_string?(value) && compiles?(value)
               elsif name == "white_space" then WHITE_SPACE.include?(value)
               elsif BOUND_FACETS.include?(name) then safe_integer?(value) || (value.is_a?(::String) && DECIMAL_TEXT.match?(value))
               else true # other facets stay caller-owned data (e.g. enumeration)
               end
          return if ok

          raise RejectedError.new(:invalid_document, klass.name,
                                  "#{klass}: facet #{name} has an invalid value #{RejectedError.show(value)}")
        end

        def compiles?(pattern)
          Regexp.new(pattern)
          true
        rescue RegexpError
          false
        end

        def safe_integer?(value)
          value.is_a?(::Integer) && value.abs <= DocumentValidator::MAX_SAFE_INTEGER
        end

        def builtin_classes
          registry = TypeRegistry.new
          Type.register_builtin_types_in(registry)
          registry.types.values
        end

        def text_problem(name, limit, json)
          return nil unless json.is_a?(::String)

          case name
          when "length", "min_length", "max_length"
            size = json.length
            ok = { "length" => size == limit, "min_length" => size >= limit, "max_length" => size <= limit }[name]
            ok ? nil : "length #{size} breaks #{name} #{limit}"
          when "pattern"
            Regexp.new("\\A(?:#{limit})\\z").match?(json) ? nil : "#{RejectedError.show(json)} does not match pattern #{limit}"
          end
        end

        def numeric_problem(name, limit, json)
          text = json.to_s
          return nil unless json.is_a?(::Integer) || (json.is_a?(::String) && DECIMAL_TEXT.match?(json))

          if BOUND_FACETS.include?(name)
            bound_problem(name, limit, text)
          elsif %w[total_digits fraction_digits].include?(name)
            digit_problem(name, limit, text)
          end
        end

        # A canonical float default is its wire string; BigDecimal reads that
        # text exactly, so the bound is compared with no Float intermediate.
        def float_bound_problem(name, limit, json)
          return nil unless json.is_a?(::String) && DocumentValidator::FLOAT_WIRE.match?(json)

          bound_problem(name, limit, json)
        end

        def bound_problem(name, limit, text)
          value = BigDecimal(text)
          edge = BigDecimal(limit.to_s)
          ok = { "min_inclusive" => value >= edge, "max_inclusive" => value <= edge,
                 "min_exclusive" => value > edge, "max_exclusive" => value < edge }[name]
          ok ? nil : "#{text} breaks #{name} #{limit}"
        end

        # XSD digit counts on the exact decimal text: sign, leading zeros and
        # trailing fraction zeros are not digits; zero counts as one digit.
        def digit_problem(name, limit, text)
          whole, fraction = text.delete("-").split(".", 2)
          fraction = fraction.to_s.sub(/0+\z/, "")
          total = (whole + fraction).sub(/\A0+/, "").length.clamp(1..)
          count = name == "total_digits" ? total : fraction.length
          count <= limit ? nil : "#{text} has #{count} digits, breaking #{name} #{limit}"
        end

        def data_copy(value, depth = 0)
          if depth >= DocumentValidator::MAX_DEPTH
            raise RejectedError.new(:invalid_document, nil, "named-value declaration nesting exceeds limit")
          end

          case value
          when ::Hash
            value.to_h do |key, item|
              unless key.is_a?(::String)
                raise RejectedError.new(:invalid_document, nil, "named-value declaration keys must be strings")
              end

              [key.dup, data_copy(item, depth + 1)]
            end
          when ::Array then value.map { |item| data_copy(item, depth + 1) }
          when ::String then value.dup
          when ::Integer, ::Float, true, false, nil then value
          else
            raise RejectedError.new(:invalid_document, nil, "named-value declarations contain data only")
          end
        end

        def freeze_tree(value)
          case value
          when ::Hash then value.each do |key, item| 
            key.freeze
            freeze_tree(item)
          end
          when ::Array then value.each { |item| freeze_tree(item) }
          end
          value.freeze
        end
      end
    end
  end
end
