# Namespace class definitions for xml_mapping_spec.rb
# Modernized from string-based to class-based XmlNamespace syntax

class XmiNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.omg.org/spec/XMI/20131001"
  prefix_default "xmi"
  element_form_default :qualified
end

class XmiNewNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.omg.org/spec/XMI/20161001"
  prefix_default "new"
  # NOTE: No element_form_default :qualified - allows default format for child elements
  # with different namespaces (see xml_mapping_spec.rb "with nil element-level namespace")
end

class MathMlNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.w3.org/1998/Math/MathML"
  prefix_default "math"  # Added to support prefix format in mixed namespaces
  element_form_default :qualified
end

class CheckNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.check.com"
  prefix_default "ns1"
  element_form_default :qualified
end

class ExampleNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.example.com"
  prefix_default "ex1"
  element_form_default :qualified
end

class GmlNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.sparxsystems.com/profiles/GML/1.0"
  prefix_default "GML"
  element_form_default :qualified
end

class CityGmlNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.sparxsystems.com/profiles/CityGML/1.0"
  prefix_default "CityGML"
  element_form_default :qualified
end

class CgmlNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.sparxsystems.com/profiles/CGML/1.0"
  prefix_default "CGML"
  element_form_default :qualified
end

class TestingDuplicateNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://testing-duplicate"
  prefix_default "td"
  element_form_default :qualified
end

class TestElementNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://test-element"
  prefix_default "te"
  element_form_default :qualified
end

class ParentNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://parent-namespace"
  prefix_default "pn"
  element_form_default :qualified
end

class ChildNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://child-namespace"
  prefix_default "cn"
  element_form_default :qualified
end

class XsdNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.w3.org/2001/XMLSchema"
  prefix_default "xsd"
  element_form_default :qualified
end

# Namespace for default_namespace_spec.rb
class ExampleNamespaceDefault < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/ns"
  # W3C default: :unqualified - children in blank namespace
  # Omit element_form_default to use W3C default behavior
end

# Namespace for mixed_content_spec.rb
class ExampleSchemaNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/schema"
  prefix_default "xsd"
  element_form_default :qualified
end

# Namespaces for xml_adapter/xml_namespace_spec.rb
class TestNamespaceNoPrefix < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/test"
  element_form_default :qualified
  # No prefix_default - will use default namespace format
end

class TestNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/test"
  prefix_default "test"
  element_form_default :qualified
end

class FooNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/foo"
  prefix_default "foo"
  element_form_default :qualified
end

class BarNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/bar"
  prefix_default "bar"
  element_form_default :qualified
end

class BazNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://example.com/baz"
  prefix_default "baz"
  element_form_default :qualified
end

class TestSchemasNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.test.com/schemas/test/1.0/"
  prefix_default "test"
  element_form_default :qualified
end

class UnitsNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://schema.example.org/units/1.0"
  element_form_default :qualified
end

# Namespace for namespace_spec.rb
class AbcNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://abc.com"
  element_form_default :qualified
end

# Namespace for xml/namespace/nested_with_explicit_namespace_spec.rb
class TestBaseNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://test-namespace"
  prefix_default "test"
  element_form_default :qualified
end

# Namespace for xml_mapping_spec.rb
class CeramicNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "https://example.com/ceramic/1.2"
  prefix_default "cer"
  element_form_default :qualified
end

# Namespaces for SchemaLocation tests
class GmlNamespace3_2 < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.opengis.net/gml/3.2"
  prefix_default "gml"
  element_form_default :qualified
end

class GmlNamespace3_7 < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.opengis.net/gml/3.7"
  prefix_default "gml"
  element_form_default :qualified
end

class XlinkNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.w3.org/1999/xlink"
  prefix_default "xlink"
  element_form_default :qualified
end

class GmdNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
  uri "http://www.isotc211.org/2005/gmd"
  prefix_default "gmd"
  element_form_default :qualified
end
