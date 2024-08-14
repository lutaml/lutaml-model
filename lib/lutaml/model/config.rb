module Lutaml
  module Model
    module Config
      extend self

      attr_accessor :xml_adapter, :json_adapter, :yaml_adapter, :toml_adapter

      def configure
        yield self
      end
    end
  end
end
