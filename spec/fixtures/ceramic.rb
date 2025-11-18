require "lutaml/model"

class HighPrecisionDateTime < Lutaml::Model::Type::DateTime
  def to_xml
    value.strftime("%Y-%m-%dT%H:%M:%S.%L%:z")
  end

  def to_json(*_args)
    value&.iso8601
  end
end

class Ceramic < Lutaml::Model::Serializable
  attribute :kiln_firing_time, HighPrecisionDateTime
  attribute :kiln_firing_time_attribute, HighPrecisionDateTime

  xml do
    root "ceramic"
    map_element "kilnFiringTime", to: :kiln_firing_time
    map_attribute "kilnFiringTimeAttribute", to: :kiln_firing_time_attribute
  end

  json do
    map "kilnFiringTime", to: :kiln_firing_time
    map "kilnFiringTimeAttribute", to: :kiln_firing_time_attribute
  end
end
