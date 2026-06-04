# frozen_string_literal: true

require "yaml"

module Lutaml
  module YamlLd
    class Adapter < Lutaml::KeyValue::Document
      def self.parse(yaml_string, _options = {})
        YAML.safe_load(
          yaml_string,
          permitted_classes: Lutaml::Yaml::Adapter::StandardAdapter::PERMITTED_CLASSES,
        )
      end

      def to_yamlld(options = {})
        YAML.dump(@attributes, options)
      end
    end
  end
end
