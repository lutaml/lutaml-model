# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      # Base class for restriction-facet collectors used by SimpleType
      # renderers. Holds the shared facet state and the `to_method_body`
      # flow that emits `options[:facet] = ...` lines inside `def self.cast`.
      #
      # Each emit step consults a `facet_steps` list — children can append
      # extra steps (XSD adds the `TRANSFORM` facet via this hook).
      #
      # Inherited by:
      #   - Lutaml::Model::Schema::XmlCompiler::Restriction
      #   - Lutaml::Model::Schema::RngCompiler::Restriction
      class Restriction
        attr_accessor :min_inclusive, :max_inclusive,
                      :min_exclusive, :max_exclusive,
                      :min_length, :max_length, :length,
                      :pattern, :enumerations, :base_type, :base_class

        # Subclasses can override or append to this list. Each entry is
        # a [predicate-method, template-constant] pair.
        FACET_STEPS = [
          [:enumerations_present?, Templates::Restriction::ENUMERATIONS],
          [:min_or_max_bound?,     Templates::Restriction::MIN_MAX_BOUNDS],
          [:pattern_present?,      Templates::Restriction::PATTERN],
        ].freeze

        def initialize
          @enumerations = []
        end

        # Returns true when at least one facet has been collected.
        def any?
          min_or_max_bound? || pattern_present? || enumerations_present? ||
            min_length || max_length || length
        end

        def to_method_body(indent = "  ")
          facet_steps.filter_map do |predicate, template|
            template.result(binding) if send(predicate)
          end.reject(&:empty?).join
        end

        # ----------------------------------------------------------------
        # Predicates. Shared names — both RNG and XSD restriction classes
        # use these now (XSD used to call them *_exist?).
        # ----------------------------------------------------------------

        def min_bound?
          !@min_inclusive.nil? || !@min_exclusive.nil?
        end

        def max_bound?
          !@max_inclusive.nil? || !@max_exclusive.nil?
        end

        def min_or_max_bound?
          min_bound? || max_bound?
        end

        def pattern_present?
          Utils.present?(@pattern)
        end

        def enumerations_present?
          !@enumerations.nil? && !@enumerations.empty?
        end

        # ----------------------------------------------------------------
        # Children override to add format-specific facets.
        # ----------------------------------------------------------------
        def facet_steps
          self.class::FACET_STEPS
        end

        private

        def casted_enumerations
          @enumerations.map { |e| "super(#{e.inspect})" }.join(", ")
        end
      end
    end
  end
end
