# Common test namespace class definitions
# Used across multiple spec files to ensure consistency

# Person fixture namespaces
class PersonNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/person"
  prefix_default "p"
  element_form_default :qualified
end

class Nsp1Namespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/nsp1"
  prefix_default "nsp1"
  element_form_default :qualified
end

# Additional common test namespaces
class XsiNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.w3.org/2001/XMLSchema-instance"
  prefix_default "xsi"
  element_form_default :qualified
end

class AnotherInstanceNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://another-instance"
  prefix_default "ai"
  element_form_default :qualified
end

class DefaultNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://default"
  element_form_default :qualified
end

class DefaultComNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://default.com"
  element_form_default :qualified
end

class ExampleComNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com"
  element_form_default :qualified
end

class ExampleDataNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/data"
  prefix_default "data"
  element_form_default :qualified
end

class ExampleDefaultNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/default"
  element_form_default :qualified
end

class ExampleDescNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/desc"
  prefix_default "desc"
  element_form_default :qualified
end

class ExampleMainNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/main"
  prefix_default "main"
  element_form_default :qualified
end

class ExampleParentNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/parent"
  prefix_default "parent"
  element_form_default :qualified
end

class ExamplePrefixedNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/prefixed"
  prefix_default "pfx"
  element_form_default :qualified
end

class ExampleRoundtripNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/roundtrip"
  prefix_default "rt"
  element_form_default :qualified
end

class ExampleStringTestNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/string-test"
  prefix_default "st"
  element_form_default :qualified
end

class PrefixComNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://prefix.com"
  prefix_default "prefix"
  element_form_default :qualified
end

class DcElementsNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://purl.org/dc/elements/1.1/"
  prefix_default "dc"
  element_form_default :qualified
end

class DcTermsNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://purl.org/dc/terms/"
  prefix_default "dcterms"
  element_form_default :qualified
end

class OfficeMathNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://schemas.openxmlformats.org/officeDocument/2006/math"
  prefix_default "m"
  element_form_default :qualified
end

class TestSimpleNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://test"
  prefix_default "test"
  element_form_default :qualified
end

class UnitsMlNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://unitsml.nist.gov/unitsml-v0.9.19"
  prefix_default "unitsml"
  element_form_default :qualified
end

class ExampleNewNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.example.com/new"
  prefix_default "new"
  element_form_default :qualified
end

class ExampleHttpsNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://example.com"
  element_form_default :qualified
end

class ExampleCatalogNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://example.com/catalog"
  prefix_default "cat"
  element_form_default :qualified
end

class CeramicNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://example.com/ceramic/1.2"
  prefix_default "cer"
  element_form_default :qualified
end

class LegacyNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://example.com/legacy"
  prefix_default "legacy"
  element_form_default :qualified
end

class ModelNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://example.com/model"
  prefix_default "model"
  element_form_default :qualified
end

class NsXsdNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://example.com/ns.xsd"
  prefix_default "ns"
  element_form_default :qualified
end

class ContactV1Namespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://example.com/schemas/contact/v1"
  prefix_default "contact"
  element_form_default :qualified
end

class ExampleTestHttpsNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://example.com/test"
  prefix_default "test"
  element_form_default :qualified
end

class VaseNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://example.com/vase/1.0"
  prefix_default "vase"
  element_form_default :qualified
end