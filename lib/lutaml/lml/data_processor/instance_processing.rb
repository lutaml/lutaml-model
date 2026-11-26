# frozen_string_literal: true

module Lutaml
  module Lml
    class DataProcessor
      module InstanceProcessing
        INSTANCE_KEY_HANDLERS = {
          instance: :process_instance,
          collections: :process_collections,
          imports: :process_imports,
          exports: :process_exports
        }.freeze

        INSTANCE_FIELD_HANDLERS = {
          instance_type: :handle_instance_type,
          isa: :handle_instance_isa,
          instance: :handle_instance_nested,
          attributes: :handle_instance_attributes,
          template: :handle_instance_template
        }.freeze

        def process_instances(obj)
          return [] unless obj.is_a?(Array)

          obj.each_with_object({}) do |instance, acc|
            acc[:instances] ||= []
            key = INSTANCE_KEY_HANDLERS.keys.find { |k| instance.key?(k) }
            next unless key

            append_result(acc, key, public_send(INSTANCE_KEY_HANDLERS[key], instance[key]))
          end
        end

        def process_instance(hash)
          hash.each_with_object({}) do |(key, value), result|
            handler = INSTANCE_FIELD_HANDLERS[key]
            if handler
              public_send(handler, value, result)
            else
              result[key] = process_value(value).last
            end
          end
        end

        def handle_instance_type(value, result)
          result[:type] = process_value(value).last
        end

        def handle_instance_isa(value, result)
          result[:isa] = process_value(value).last
        end

        def handle_instance_nested(value, result)
          result[:instance] = process_instance(value)
        end

        def handle_instance_attributes(value, result)
          result[:attributes] = process_attributes(value)
        end

        def handle_instance_template(value, result)
          result[:template] = process_attributes(value[:attributes])
        end

        private

        def append_result(acc, key, result)
          case key
          when :instance then acc[:instances] << result
          when :collections then (acc[:collections] ||= []) << result
          else (acc[key] ||= []).concat(result)
          end
        end
      end
    end
  end
end
