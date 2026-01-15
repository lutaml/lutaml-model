# frozen_string_literal: true

require_relative "namespace_declaration"

module Lutaml
  module Model
    module Xml
      # NamespaceDeclarationBuilder - Build xmlns attributes from DeclarationPlan
      #
      # REFACTORED (Session 176):
      # Builds xmlns strings from NamespaceDeclaration DATA
      # NO MORE reading pre-built xmlns_declaration strings
      #
      # REFACTORED (Session 182):
      # Added build_all_xmlns_attributes to include Type namespace declarations
      #
      # CRITICAL ARCHITECTURAL PRINCIPLE:
      # Adapters build XML strings from data
      # Planning produces data, rendering produces XML
      #
      # PURPOSE:
      # Converts namespace declarations from a DeclarationPlan into xmlns attributes
      # for XML element construction.
      #
      # USAGE:
      #   attributes = NamespaceDeclarationBuilder.build_all_xmlns_attributes(plan)
      #
      module NamespaceDeclarationBuilder
        # Build ALL xmlns attributes from plan (regular + Type namespaces)
        #
        # CRITICAL (Session 197): Type namespaces are now handled by DeclarationPlanner
        # and stored in the plan like any other namespace. No special handling needed.
        # This enforces the "Dumb Adapter" principle - rendering only reads from plan.
        #
        # @param plan [DeclarationPlan] the declaration plan
        # @return [Hash] attributes hash with all xmlns declarations
        def self.build_all_xmlns_attributes(plan)
          # DUMB ADAPTER: Just build from plan, no decisions
          build_xmlns_attributes(plan)
        end

        # Build xmlns attributes from namespace declarations in plan
        #
        # @param plan [DeclarationPlan] the declaration plan with tree structure
        # @return [Hash] attributes hash with xmlns declarations
        def self.build_xmlns_attributes(plan)
          attributes = {}

          # Read from tree structure
          plan.root_node.hoisted_declarations.each do |key, uri|
            # CRITICAL: Never declare xml namespace - it's implicitly bound
            next if uri == "http://www.w3.org/XML/1998/namespace"

            # Build xmlns attribute based on key type:
            # nil = default namespace (xmlns="uri")
            # String = prefixed namespace (xmlns:prefix="uri")
            if key.nil?
              # Default namespace
              attributes["xmlns"] = uri
            else
              # Prefixed namespace
              attributes["xmlns:#{key}"] = uri
            end
          end

          attributes
        end
      end
    end
  end
end