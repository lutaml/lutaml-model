# frozen_string_literal: true

# Opal runtime patches for lutaml-model specs
if RUBY_ENGINE == "opal"
  Lutaml::Model::Config.xml_adapter_type = :rexml
end
