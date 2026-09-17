# frozen_string_literal: true

require "json"
require_relative "../json/generator_options"

module Lutaml
  module JsonLd
    class Adapter < Lutaml::KeyValue::Document
      def self.parse(jsonld_string, _options = {})
        JSON.parse(jsonld_string)
      end

      def to_jsonld(*args)
        data = @attributes

        unless Lutaml::Json::GeneratorOptions.lutaml_options?(args.first)
          return JSON.generate(data, args.first)
        end

        options = args.first || {}
        generator_options = Lutaml::Json::GeneratorOptions.filter(options)

        if options[:pretty]
          JSON.pretty_generate(data, generator_options)
        else
          JSON.generate(data, generator_options)
        end
      end
    end
  end
end
