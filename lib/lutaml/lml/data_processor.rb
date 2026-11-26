# frozen_string_literal: true

module Lutaml
  module Lml
    # Post-transform normalization: turns parse captures into the flat
    # member hashes the document builder consumes.
    class DataProcessor
      autoload :ValueProcessing, "lutaml/lml/data_processor/value_processing"
      autoload :AttributeProcessing, "lutaml/lml/data_processor/attribute_processing"
      autoload :ValueDeclarationProcessing, "lutaml/lml/data_processor/value_declaration_processing"
      autoload :InstanceProcessing, "lutaml/lml/data_processor/instance_processing"
      autoload :CollectionProcessing, "lutaml/lml/data_processor/collection_processing"
      autoload :ViewProcessing, "lutaml/lml/data_processor/view_processing"

      include ValueProcessing
      include AttributeProcessing
      include ValueDeclarationProcessing
      include InstanceProcessing
      include CollectionProcessing
      include ViewProcessing

      KEY_HANDLERS = {
        lml_version: :process_lml_version,
        requires: :process_requires,
        instances: :process_instances,
        instance: :process_instance,
        attributes: :process_attributes,
        value_decl: :process_value_declaration,
        show_list: :process_show_list,
        hide_list: :process_hide_list,
      }.freeze

      def self.process(obj)
        new.process_data(obj)
      end

      def process_data(obj)
        return obj unless obj.is_a?(Hash) || obj.is_a?(Array)

        obj.is_a?(Array) ? obj.map { |item| process_data(item) } : process_hash(obj)
      end

      def process_hash(obj)
        obj.each_with_object({}) do |(key, value), result|
          handler = KEY_HANDLERS[key]
          result[key] = handler ? public_send(handler, value) : process_data(value)
        end
      end

      def process_requires(obj)
        obj.map { |req| process_value(req).last }
      end

      def process_lml_version(value)
        value.is_a?(Hash) ? value[:string] : value
      end
    end
  end
end
