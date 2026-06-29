# frozen_string_literal: true

# Opal runtime patches for lutaml-model specs.
# Oga (via moxml's vendored opal-oga fork) is the only XML adapter that
# works under Opal — REXML has runtime issues that moxml's CI proved.
if RUBY_ENGINE == "opal"
  Lutaml::Model::Config.xml_adapter_type = :oga
end
