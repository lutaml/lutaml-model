# frozen_string_literal: true

module Lutaml
  module Xml
    module TransformationSupport
      autoload :CustomMethodWrapper,
               "#{__dir__}/transformation/custom_method_wrapper"
      autoload :RuleCompiler, "#{__dir__}/transformation/rule_compiler"
      autoload :SkipLogic, "#{__dir__}/transformation/skip_logic"
      autoload :ValueSerializer, "#{__dir__}/transformation/value_serializer"
      autoload :ElementBuilder, "#{__dir__}/transformation/element_builder"
      autoload :OrderedApplier, "#{__dir__}/transformation/ordered_applier"
      autoload :RuleApplier, "#{__dir__}/transformation/rule_applier"
    end
  end
end
