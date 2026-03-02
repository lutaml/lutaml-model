# frozen_string_literal: true

# Memory profiling script for Lutaml::Model XML operations
# Usage: bundle exec ruby lib/tasks/memory_profile.rb

require "memory_profiler"
require "lutaml/model"

# Configure adapters
Lutaml::Model::Config.xml_adapter_type = :nokogiri
Lutaml::Model::Config.json_adapter_type = :standard_json

# Test models
class Address < Lutaml::Model::Serializable
  attribute :street, :string
  attribute :city, :string
  attribute :zip, :string
  attribute :country, :string

  xml do
    root "address"
    map_element "street", to: :street
    map_element "city", to: :city
    map_element "zip", to: :zip
    map_element "country", to: :country
  end
end

class Person < Lutaml::Model::Serializable
  attribute :id, :integer
  attribute :first_name, :string
  attribute :last_name, :string
  attribute :email, :string
  attribute :age, :integer
  attribute :address, Address
  attribute :phone_numbers, :string, collection: true
  attribute :tags, :string, collection: true

  xml do
    root "person"
    map_attribute "id", to: :id
    map_element "first_name", to: :first_name
    map_element "last_name", to: :last_name
    map_element "email", to: :email
    map_element "age", to: :age
    map_element "address", to: :address
    map_element "phone_number", to: :phone_numbers
    map_element "tag", to: :tags
  end
end

# Test data
def person_xml
  <<~XML
    <person id="123">
      <first_name>John</first_name>
      <last_name>Doe</last_name>
      <email>john@example.com</email>
      <age>30</age>
      <address>
        <street>123 Main St</street>
        <city>City</city>
        <zip>12345</zip>
        <country>Country</country>
      </address>
      <phone_number>555-1000</phone_number>
      <phone_number>555-2000</phone_number>
      <tag>tag1</tag>
      <tag>tag2</tag>
    </person>
  XML
end

def person_instance
  Person.new(
    id: 123,
    first_name: "John",
    last_name: "Doe",
    email: "john@example.com",
    age: 30,
    address: Address.new(
      street: "123 Main St",
      city: "City",
      zip: "12345",
      country: "Country",
    ),
    phone_numbers: ["555-1000", "555-2000"],
    tags: ["tag1", "tag2"],
  )
end

# Number of iterations for profiling
ITERATIONS = 10

puts "=" * 80
puts "Lutaml::Model Memory Profile (#{ITERATIONS} iterations)"
puts "=" * 80
puts

# Profile from_xml (parsing)
puts "-" * 40
puts "Person.from_xml Memory Profile"
puts "-" * 40

from_xml_report = MemoryProfiler.report do
  ITERATIONS.times { Person.from_xml(person_xml) }
end

from_xml_report.pretty_print(
  scale_bytes: true,
  normalize_paths: true,
  allocated_types: 30,
  allocated_files: 15,
)

puts
puts "Summary (from_xml):"
puts "  Total allocated: #{from_xml_report.total_allocated_memsize_bytes} bytes"
puts "  Total retained: #{from_xml_report.total_retained_memsize_bytes} bytes"
puts

# Profile to_xml (serialization)
puts "-" * 40
puts "Person.to_xml Memory Profile"
puts "-" * 40

person = person_instance

to_xml_report = MemoryProfiler.report do
  ITERATIONS.times { person.to_xml }
end

to_xml_report.pretty_print(
  scale_bytes: true,
  normalize_paths: true,
  allocated_types: 30,
  allocated_files: 15,
)

puts
puts "Summary (to_xml):"
puts "  Total allocated: #{to_xml_report.total_allocated_memsize_bytes} bytes"
puts "  Total retained: #{to_xml_report.total_retained_memsize_bytes} bytes"
puts

# Profile Person.new (model creation)
puts "-" * 40
puts "Person.new Memory Profile"
puts "-" * 40

new_report = MemoryProfiler.report do
  ITERATIONS.times { person_instance }
end

new_report.pretty_print(
  scale_bytes: true,
  normalize_paths: true,
  allocated_types: 30,
  allocated_files: 15,
)

puts
puts "Summary (Person.new):"
puts "  Total allocated: #{new_report.total_allocated_memsize_bytes} bytes"
puts "  Total retained: #{new_report.total_retained_memsize_bytes} bytes"
puts

# Combined summary
puts "=" * 80
puts "OVERALL SUMMARY"
puts "=" * 80
puts
puts "Per iteration allocations:"
puts "  from_xml: #{from_xml_report.total_allocated_memsize_bytes / ITERATIONS} bytes"
puts "  to_xml:   #{to_xml_report.total_allocated_memsize_bytes / ITERATIONS} bytes"
puts "  Person.new: #{new_report.total_allocated_memsize_bytes / ITERATIONS} bytes"
