# frozen_string_literal: true

# Opal runtime YAML compat.
#
# Opal's `nodejs/yaml` ships `YAML.load` only. lutaml-model's YAML adapter
# uses `YAML.safe_load(src, permitted_classes: [...])` and `YAML.dump(obj)`.
# Provide both as thin wrappers — nodejs/yaml is already backed by
# jsyaml.safeLoad, so `load` semantics are equivalent to MRI's safe_load
# with the default permitted classes (the perm_classes argument is
# accepted but ignored, matching Opal's stronger-by-default posture).

if RUBY_ENGINE == "opal"
  require "nodejs/yaml"

  module ::YAML
    class << self
      # Accept MRI's full safe_load kwargs for API parity; nodejs/yaml's
      # safeLoad is already safe-by-default so the kwargs are unused.
      def safe_load(yaml, **_kwargs)
        load(yaml)
      end

      def dump(obj, io = nil)
        dumped = `#{@__yaml__}.safeDump(#{obj})`
        return dumped unless io

        io.write(dumped)
        io
      end
    end
  end
end
