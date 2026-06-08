# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # Stateless traversal helpers for the heterogeneous `members`
        # array of a Definitions::Model. Definitions stay as pure data;
        # the walk logic lives here so consumers (XmlCompiler /
        # RngCompiler dependency collection, future visitors) don't each
        # re-implement the same case-dispatch.
        module MemberWalk
          module_function

          # Yields every Attribute leaf, recursing into Sequence members
          # and Choice alternatives. Returns an Enumerator when called
          # without a block.
          def each_attribute(members, &block)
            return enum_for(:each_attribute, members) unless block_given?

            members.each do |member|
              case member
              when Attribute then yield member
              when Sequence  then each_attribute(member.members, &block)
              when Choice    then each_attribute(member.alternatives, &block)
              end
            end
          end
        end
      end
    end
  end
end
