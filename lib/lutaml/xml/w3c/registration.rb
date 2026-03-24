# frozen_string_literal: true

module Lutaml
  module Xml
    module W3c
      extend self

      # W3C types mapped to their symbol identifiers for Type registry
      W3C_TYPES = {
        xml_lang: XmlLangType,
        xml_space: XmlSpaceType,
        xml_base: XmlBaseType,
        xml_id: XmlIdType,
        xsi_type: XsiType,
        xsi_nil: XsiNil,
        xsi_schema_location: XsiSchemaLocationType,
        xsi_no_namespace_schema_location: XsiNoNamespaceSchemaLocationType,
        xlink_href: XlinkHrefType,
        xlink_type: XlinkTypeAttrType,
        xlink_role: XlinkRoleType,
        xlink_arcrole: XlinkArcroleType,
        xlink_title: XlinkTitleType,
        xlink_show: XlinkShowType,
        xlink_actuate: XlinkActuateType,
      }.freeze

      # Register all W3C types with the Type registry.
      # Called lazily when types are first accessed.
      #
      # @return [Boolean] true if registration succeeded or already done
      def register_types!
        return true if @types_registered

        if defined?(Lutaml::Model::Type)
          W3C_TYPES.each do |symbol, type_class|
            Lutaml::Model::Type.register(symbol, type_class)
          end
          @types_registered = true
        end
        @types_registered
      end

      # Automatically register types when a constant is accessed via const_missing.
      # This ensures symbol-based type access works even if autoload order
      # causes w3c.rb to load before lutaml-model's Type module.
      def const_missing(name)
        register_types!
        const_get(name)
      end
    end
  end
end
