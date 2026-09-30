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

      def self.plan_path_compatible?
        return false unless defined?(Gem)

        spec = Gem.loaded_specs["leptris"]
        spec && spec.version >= Gem::Version.new(MIN_LEPTRIS_VERSION)
      end

      autoload :PlanCompiler, "lutaml/xml/leptris/plan_compiler"
      autoload :PlanHydrator, "lutaml/xml/leptris/plan_hydrator"
      autoload :PlanOrder, "lutaml/xml/leptris/plan_order"
      autoload :PlanSerializer, "lutaml/xml/leptris/plan_serializer"
      autoload :PlanWalk, "lutaml/xml/leptris/plan_walk"
    end
  end
end
