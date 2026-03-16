require "erb"
require "ostruct"

module Lutaml
  module Model
    module Schema
      class Renderer
        def self.render(template_path, variables = {})
          new(template_path).render(variables)
        end

        def initialize(template_path)
          @template = File.read(template_path)
        end

        def render(variables = {})
          context = build_context(variables)

          ERB.new(@template, trim_mode: "-").result(context.instance_eval { binding })
        end

        private

        def build_context(variables)
          context = Context.new(variables)
          context.extend(Lutaml::Model::Schema::Helpers::TemplateHelper)
          context
        end

        # Simple OpenStruct-based context that allows flexible variable access
        class Context < OpenStruct
        end
      end
    end
  end
end
