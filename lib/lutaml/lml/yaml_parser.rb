# frozen_string_literal: true

require "yaml"

module Lutaml
  module Lml
    class YamlParser
      def self.parse(yaml_path, options = {})
        new.parse(yaml_path, options)
      end

      def parse(yaml_path, _options = {})
        Lutaml::Lml::Document.from_yaml(File.read(yaml_path))
      end
    end
  end
end
