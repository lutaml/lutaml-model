# frozen_string_literal: true

module Lutaml
  module Xml
    module Decisions
      autoload :Decision, "#{__dir__}/decisions/decision"
      autoload :DecisionContext, "#{__dir__}/decisions/decision_context"
      autoload :DecisionRule, "#{__dir__}/decisions/decision_rule"
      autoload :DecisionEngine, "#{__dir__}/decisions/decision_engine"
      autoload :ElementPrefixResolver, "#{__dir__}/decisions/element_prefix_resolver"
      autoload :Rules, "#{__dir__}/decisions/rules"
    end
  end
end
