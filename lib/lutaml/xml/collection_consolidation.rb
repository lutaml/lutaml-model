# frozen_string_literal: true

module Lutaml
  module Xml
    # Shared XML post-processing for interpreted mappings and native plans.
    # Organization belongs to the collection's XML mapping; both parse paths
    # must run it after all attributes, deferred mappings and delegates settle.
    module CollectionConsolidation
      def self.call(instance, register, instance_is_serialize = nil)
        return unless instance_is_serialize || instance.is_a?(::Lutaml::Model::Serialize)

        instance.class.attributes.each_value do |attr|
          next unless attr.collection?
          next unless attr.custom_collection?

          collection = instance.public_send(attr.name)
          next unless collection.is_a?(::Lutaml::Model::Collection)
          next unless collection.class.organization

          mappings = collection.class.mappings_for(:xml, register)
          next unless mappings.is_a?(::Lutaml::Xml::Mapping)
          next if mappings.consolidation_maps.empty?

          mappings.consolidation_maps.each do |map|
            org = collection.class.organization
            resolved_map = if map.group_class
                             map
                           else
                             ::Lutaml::Model::ConsolidationMap.new(
                               by: map.by,
                               to: map.to,
                               group_class: org.group_class,
                               rules: map.rules,
                             )
                           end
            ::Lutaml::Model::Consolidation::Engine.run(
              collection, resolved_map, collection.collection
            )
          end
        end
      end
    end
  end
end
