# frozen_string_literal: true

# JS bundle entry point. Pulls in the Opal-only compat shims and boot
# files BEFORE lutaml/model so that moxml's adapter constants, the
# String/Encoding/YAML/Array#pack patches, and the eager-loaded
# Moxml::* / Lutaml::* constants are all in place by the time
# lib/lutaml/model.rb runs.
#
# Used by scripts/build.rb as the bundle ENTRY (instead of
# "lutaml/model" directly) so the JS bundle mirrors the load order
# that lutaml-model's Rakefile applies for `rake spec:opal`.

if RUBY_ENGINE == "opal"
  # 0. runtime_compatibility first: it stubs Mutex/ConditionVariable/
  #    Thread/WeakRef and patches Module#prepend for Opal. Oga's LRU
  #    and other gems reference Mutex at file-load time, so this must
  #    run before any gem that touches thread-safety primitives.
  require "lutaml/model/runtime_compatibility"

  # 0a. Opal's stdlib StringIO < IO loads here so moxml's
  #     `class StringIO` (bare, no parent) in rexml_compat.rb re-opens
  #     the existing class instead of conflicting with `< ::IO`.
  #     Without this, the bare-class definition runs first and Opal's
  #     `< IO` definition later raises "superclass mismatch".
  require "stringio"

  # 1. stdlib shims: String/Encoding/StringIO + Array#pack + nodejs/yaml
  require "rexml_compat"
  require "yaml_compat"

  # 2. forks' Opal-aware conditionals select the pure-Ruby lexer
  require "oga"
  require "ll/setup"

  # 3. eager-load boots (Opal ignores autoload)
  require "moxml_boot"
  require "lutaml_model_boot"
end

# 4. the actual entry point
require "lutaml/model"
require "lutaml/xml"
