# frozen_string_literal: true

require "pry"
require "lutaml"
require_relative "lml_compiler/class"

module Lutaml
  module Model
    module Schema
      module LmlCompiler
        extend self

        attr_accessor :classes_list

        def to_models(schema, options = {})
          as_models(schema)

          if options[:create_files]
            dir = options.fetch(:output_dir, "lutaml_models_#{Time.now.to_i}")
            classes_list.each { |name, klass| create_file(name, klass, dir) }
            true
          else
            require_classes(classes_list) if options[:load_classes]
            classes_list
          end
        end

        def create_file(name, content, dir)
          path = name.split("::")
          name = path.pop
          dir = File.join(dir, *path.map { |p| Utils.snake_case(p) })
          FileUtils.mkdir_p(dir)
          File.write("#{dir}/#{Utils.snake_case(name)}.rb", content)
        end

        def require_classes(classes_hash)
          Dir.mktmpdir do |dir|
            classes_hash.each { |name, klass| create_file(name, klass, dir) }
            # Some files are not created at the time of the require, so we need to require them after all the files are created.
            classes_hash.each_key { |name| require "#{dir}/#{Utils.snake_case(name)}" }
          end
        end

        def as_models(schema)
          parsed = Parser.parse(schema).first

          @classes_list = parsed.classes.to_h do |klass|
            ["#{parsed.name}::#{klass.name}", Class.new(klass, enums: parsed.enums, namespace: parsed.name).to_class]
          end
        end
      end
    end
  end
end
