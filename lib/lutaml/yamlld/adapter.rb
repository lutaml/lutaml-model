# frozen_string_literal: true

require "yaml"

module Lutaml
  module YamlLd
    class Adapter < Lutaml::KeyValue::Document
      PERMITTED_CLASSES = Lutaml::Yaml::Adapter::StandardAdapter::PERMITTED_CLASSES

      def self.parse(yaml_string, _options = {})
        YAML.safe_load(yaml_string, permitted_classes: PERMITTED_CLASSES)
      end

      def to_yamlld(options = {})
        attributes_to_serialize =
          if @attributes.is_a?(Lutaml::KeyValue::DataModel::Element)
            @attributes.to_hash["__root__"]
          else
            @attributes
          end
        YAML.dump(attributes_to_serialize, options)
      end
    end
  end
end
