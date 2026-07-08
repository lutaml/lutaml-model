# frozen_string_literal: true

# Opal runtime patches for lutaml-model specs.
# Oga (via moxml's vendored opal-oga fork) is the default XML adapter
# under Opal; REXML (bundled stdlib gem, pure Ruby) is also available.
# Smoke specs parameterize over both — see spec/lutaml/xml/opal_xml_spec.rb.
if RUBY_ENGINE == "opal"
  Lutaml::Model::Config.xml_adapter_type = :oga
end
