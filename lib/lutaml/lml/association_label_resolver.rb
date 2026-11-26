# frozen_string_literal: true

module Lutaml
  module Lml
    class AssociationLabelResolver
      def enrich(document)
        class_index = build_class_index(document)
        document.associations.each do |assoc|
          enrich_owner_end(assoc, class_index)
          enrich_member_end(assoc, class_index)
        end
        document
      end

      private

      def build_class_index(document)
        document.all_classes.each_with_object({}) { |klass, index| index[klass.name] = klass }
      end

      def enrich_owner_end(assoc, class_index)
        return if assoc.owner_end_attribute_name

        owner_class = class_index[assoc.owner_end.to_s]
        return unless owner_class

        attr = find_attribute_by_type(owner_class, assoc.member_end.to_s)
        return unless attr

        assoc.owner_end_attribute_name = attr.name
        assoc.owner_end_cardinality = attr.cardinality if attr.cardinality
      end

      def enrich_member_end(assoc, class_index)
        return if assoc.member_end_attribute_name

        member_class = class_index[assoc.member_end.to_s]
        return unless member_class

        attr = find_attribute_by_type(member_class, assoc.owner_end.to_s)
        return unless attr

        assoc.member_end_attribute_name = attr.name
        assoc.member_end_cardinality = attr.cardinality if attr.cardinality
      end

      def find_attribute_by_type(klass, target_type_name)
        klass.attributes&.find { |a| a.type == target_type_name }
      end
    end
  end
end
