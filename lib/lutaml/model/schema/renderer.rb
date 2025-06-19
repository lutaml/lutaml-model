require "erb"
require "ostruct"

require_relative "helpers/template_helper"

module Lutaml
  module Model
    module Schema
      class Context
        include Lutaml::Model::Schema::Helpers::TemplateHelper

        attr_reader :schema

        def initialize(schema)
          @schema = schema
        end
      end

      class Renderer
        def self.render(template_path, context = {})
          new(template_path).render(context)
        end

        def initialize(template_path)
          @template = File.read(template_path)
        end

        def render(context = {})
          context = Context.new(context[:schema])

          ERB.new(@template, trim_mode: "-").result(context.instance_eval { binding })
        end
      end
    end
  end
end
