# frozen_string_literal: true

require "json"

module Lutaml
  module JsonLd
    class Adapter < Lutaml::KeyValue::Document
      def self.parse(jsonld_string, _options = {})
        JSON.parse(jsonld_string, create_additions: false)
      end

      def to_jsonld(*args)
        options = args.first || {}
        data = @attributes
        if options[:pretty]
          JSON.pretty_generate(data, *args)
        else
          JSON.generate(data, *args)
        end
      end
    end
  end
end
