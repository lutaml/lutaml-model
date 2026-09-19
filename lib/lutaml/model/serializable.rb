# frozen_string_literal: true

module Lutaml
  module Model
    class Serializable
      # ComparableModel is included at the Serialize module level; its
      # ClassMethods (diff_with_score) must extend the class that
      # model classes actually inherit from (lutaml-model#18).
      include Serialize
      extend ComparableModel::ClassMethods
    end
  end
end
