# frozen_string_literal: true

module Lutaml
  module Xml
    module Decisions
    end
  end
end

module Lutaml
  module Xml
    module Decisions
      module Rules
        autoload :InheritFromParentRule,
                 "#{__dir__}/rules/inherit_from_parent_rule"
        autoload :ElementFormDefaultUnqualifiedRule,
                 "#{__dir__}/rules/element_form_default_unqualified_rule"
        autoload :HoistedOnParentRule, "#{__dir__}/rules/hoisted_on_parent_rule"
        autoload :ElementFormOptionRule,
                 "#{__dir__}/rules/element_form_option_rule"
        autoload :ReuseParentPrefixRule,
                 "#{__dir__}/rules/reuse_parent_prefix_rule"
        autoload :FormatPreservationRule,
                 "#{__dir__}/rules/format_preservation_rule"
        autoload :ExplicitOptionRule, "#{__dir__}/rules/explicit_option_rule"
        autoload :NamespaceScopeRule, "#{__dir__}/rules/namespace_scope_rule"
        autoload :AttributeUsageRule, "#{__dir__}/rules/attribute_usage_rule"
        autoload :ElementFormDefaultRule,
                 "#{__dir__}/rules/element_form_default_rule"
        autoload :DefaultPreferenceRule,
                 "#{__dir__}/rules/default_preference_rule"
        autoload :InheritParentPrefixRule,
                 "#{__dir__}/rules/inherit_parent_prefix_rule"
      end
    end
  end
end
