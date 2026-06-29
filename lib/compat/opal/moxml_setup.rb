# frozen_string_literal: true

# Opal runtime setup for moxml and lutaml-model.
#
# Released moxml 0.1.23 still ships OPAL_DEFAULT_ADAPTER = :rexml, which
# fails to load under Opal (REXML has runtime issues that moxml's main
# branch has since fixed by switching the default to :oga). Until a new
# moxml release lands, force the default to :oga here so any moxml
# initialization that reads Config.default picks the right adapter.
#
# Also loads nodejs/yaml because Opal's bundled `require "yaml"` was
# removed and now requires the explicit nodejs/yaml shim. lutaml-model's
# YAML adapter depends on the YAML module being defined.
#
# This file must run before any code path that triggers
# Moxml::Config.default (e.g. Moxml.configure) or YAML usage. The
# Rakefile puts it ahead of lutaml_model_boot in the runner.requires list.

if RUBY_ENGINE == "opal"
  require "moxml/config"
  Moxml::Config.default_adapter = :oga
end
