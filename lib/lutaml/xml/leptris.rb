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

      # Nested child plans capture their declared attribute rows when
      # the parent plan carries an exact-URI attribute row: the
      # two-level shape binds as of 1.9.313.0, but three-level and
      # deeper subtrees (fonts -> font -> panose1 under an mc:Ignorable
      # row) still drop attribute capture (leptris#1563 remains open).
      # Those models stay interpretive until the engine fix lands.
      MIN_LEPTRIS_NESTED_ATTR_VERSION = "99.0.0"

      # Wildcard child rows (leptris#1552: named-rows-take-precedence
      # two-pass walk, ns-form aware, type_tag echo) — the plan path's
      # map_any_element catch-all. Ships with the 1.9.313 binding.
      MIN_LEPTRIS_WILDCARD_VERSION = "1.9.313.0"

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

      autoload :PlanCompiler, "lutaml/xml/leptris/plan_compiler"
      autoload :PlanHydrator, "lutaml/xml/leptris/plan_hydrator"
      autoload :PlanOrder, "lutaml/xml/leptris/plan_order"
      autoload :PlanSerializer, "lutaml/xml/leptris/plan_serializer"
      autoload :PlanWalk, "lutaml/xml/leptris/plan_walk"
    end
  end
end
