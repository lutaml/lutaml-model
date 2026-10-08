# frozen_string_literal: true

module Lutaml
  module Xml
    # The leptris plan fast path: model mapping to libleptris descriptor
    # plan, native walk, direct hydration. Everything under this
    # namespace is bound to the leptris gem; nothing above it may
    # reference leptris types directly (the moxml adapters and the
    # interpretive path never enter here).
    module Leptris
      # The plan path requires the one-crossing child snapshot
      # (leptris_plan_value_children_snapshot with child handles,
      # PlanValue#children_snapshot), which shipped in leptris
      # 1.9.273.0. Bundles resolving an older gem keep the
      # interpretive path — PlanCompiler.compile answers nil — the
      # existing opt-out protocol.
      MIN_LEPTRIS_VERSION = "1.9.273.0"

      # AttrPlan rows carrying an ns form (exact-URI attribute matching,
      # leptris#1486) shipped in libleptris 1.9.289.0. Older gems keep
      # type-namespaced attributes on the interpretive path.
      MIN_LEPTRIS_ATTR_NS_VERSION = "1.9.289.0"

      # Nested child plans capture their declared attribute rows
      # correctly again as of 1.9.313.0 (leptris#1563: the walk dropped
      # children's attribute capture when the parent plan carried an
      # exact-URI attribute row). Older gems keep those models
      # interpretive.
      MIN_LEPTRIS_NESTED_ATTR_VERSION = "1.9.313.0"

      # Wildcard child rows (leptris#1552: named-rows-take-precedence
      # two-pass walk, ns-form aware, type_tag echo) — the plan path's
      # map_any_element catch-all. Ships with the 1.9.313 binding.
      MIN_LEPTRIS_WILDCARD_VERSION = "1.9.313.0"

      # Walk-side namespace safety (leptris#1587, closing #1585 and
      # #1586): child-row exact-URI ns_uri is retained engine-side
      # (deep-copied at build, freed with the plan) and plain attribute
      # rows leniently match namespace-qualified wire attributes
      # (exact-first-then-any, top level and nested). Both shipped in
      # 1.9.320.0; older engines keep the affected models interpretive
      # through PlanCompiler.engine_walk_safe?.
      MIN_LEPTRIS_WALK_NS_SAFETY_VERSION = "1.9.320.0"

      def self.plan_path_compatible?
        return false unless defined?(Gem)

        spec = Gem.loaded_specs["leptris"]
        spec && spec.version >= Gem::Version.new(MIN_LEPTRIS_VERSION)
      end

      def self.attr_ns_rows_compatible?
        return false unless defined?(Gem)

        spec = Gem.loaded_specs["leptris"]
        spec && spec.version >= Gem::Version.new(MIN_LEPTRIS_ATTR_NS_VERSION)
      end

      def self.nested_attr_capture_compatible?
        return false unless defined?(Gem)

        spec = Gem.loaded_specs["leptris"]
        spec && spec.version >= Gem::Version.new(MIN_LEPTRIS_NESTED_ATTR_VERSION)
      end

      def self.wildcard_rows_compatible?
        return false unless defined?(Gem)

        spec = Gem.loaded_specs["leptris"]
        spec && spec.version >= Gem::Version.new(MIN_LEPTRIS_WILDCARD_VERSION)
      end

      # Memoized: consulted per parse on the walk gate hot path, and
      # the loaded leptris spec cannot change within a process.
      @walk_ns_safety = nil
      def self.walk_ns_safety_compatible?
        return @walk_ns_safety unless @walk_ns_safety.nil?
        return (@walk_ns_safety = false) unless defined?(Gem)

        spec = Gem.loaded_specs["leptris"]
        @walk_ns_safety =
          !!(spec && spec.version >= Gem::Version.new(MIN_LEPTRIS_WALK_NS_SAFETY_VERSION))
      end

      autoload :PlanCompiler, "lutaml/xml/leptris/plan_compiler"
      autoload :PlanHydrator, "lutaml/xml/leptris/plan_hydrator"
      autoload :PlanOrder, "lutaml/xml/leptris/plan_order"
      autoload :PlanSerializer, "lutaml/xml/leptris/plan_serializer"
      autoload :PlanWalk, "lutaml/xml/leptris/plan_walk"
    end
  end
end
