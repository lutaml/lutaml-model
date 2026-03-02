# frozen_string_literal: true

require "benchmark/ips"
require "lutaml/model"

# Configure adapters
Lutaml::Model::Config.xml_adapter_type = :nokogiri
Lutaml::Model::Config.json_adapter_type = :standard_json

module Lutaml
  module Model
    module Performance
      # Shared test models for benchmarks
      module TestModels
        # Simple model with basic types
        class SimpleModel < Lutaml::Model::Serializable
          attribute :id, :integer
          attribute :name, :string
          attribute :active, :boolean
          attribute :score, :float
          attribute :created_at, :date_time

          xml do
            root "simple"
            map_attribute "id", to: :id
            map_element "name", to: :name
            map_element "active", to: :active
            map_element "score", to: :score
            map_element "created_at", to: :created_at
          end

          key_value do
            map "id", to: :id
            map "name", to: :name
            map "active", to: :active
            map "score", to: :score
            map "created_at", to: :created_at
          end
        end

        # Nested model for testing relationships
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

          key_value do
            map "street", to: :street
            map "city", to: :city
            map "zip", to: :zip
            map "country", to: :country
          end
        end

        # Complex model with nested objects and collections
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

          key_value do
            map "id", to: :id
            map "first_name", to: :first_name
            map "last_name", to: :last_name
            map "email", to: :email
            map "age", to: :age
            map "address", to: :address
            map "phone_numbers", to: :phone_numbers
            map "tags", to: :tags
          end
        end

        # Deeply nested model
        class OrderItem < Lutaml::Model::Serializable
          attribute :product_id, :integer
          attribute :quantity, :integer
          attribute :price, :float

          xml do
            root "item"
            map_attribute "product_id", to: :product_id
            map_element "quantity", to: :quantity
            map_element "price", to: :price
          end
        end

        class Order < Lutaml::Model::Serializable
          attribute :id, :integer
          attribute :customer, Person
          attribute :items, OrderItem, collection: true
          attribute :total, :float
          attribute :status, :string

          xml do
            root "order"
            map_attribute "id", to: :id
            map_element "customer", to: :customer
            map_element "item", to: :items
            map_element "total", to: :total
            map_element "status", to: :status
          end
        end

        # Generate test data
        class << self
          def simple_model_xml(count: 1)
            items = count.times.map do |i|
              <<~XML
                <simple id="#{i}">
                  <name>Test Name #{i}</name>
                  <active>true</active>
                  <score>#{i}.5</score>
                  <created_at>2024-01-#{(i % 28) + 1}T10:00:00Z</created_at>
                </simple>
              XML
            end
            items.join("\n")
          end

          def person_xml(count: 1)
            people = count.times.map do |i|
              <<~XML
                <person id="#{i}">
                  <first_name>John#{i}</first_name>
                  <last_name>Doe#{i}</last_name>
                  <email>john#{i}@example.com</email>
                  <age>#{25 + (i % 50)}</age>
                  <address>
                    <street>#{i} Main St</street>
                    <city>City#{i}</city>
                    <zip>#{10000 + i}</zip>
                    <country>Country#{i % 10}</country>
                  </address>
                  <phone_number>555-#{1000 + i}</phone_number>
                  <phone_number>555-#{2000 + i}</phone_number>
                  <tag>tag#{i % 5}</tag>
                  <tag>tag#{(i + 1) % 5}</tag>
                </person>
              XML
            end
            people.join("\n")
          end

          def order_xml(count: 1)
            orders = count.times.map do |i|
              items_xml = 5.times.map do |j|
                <<~XML
                  <item product_id="#{i * 10 + j}">
                    <quantity>#{j + 1}</quantity>
                    <price>#{(j + 1) * 9.99}</price>
                  </item>
                XML
              end.join

              <<~XML
                <order id="#{i}">
                  <customer id="#{i * 100}">
                    <first_name>Customer</first_name>
                    <last_name>#{i}</last_name>
                    <email>customer#{i}@example.com</email>
                    <age>30</age>
                    <address>
                      <street>#{i} Order St</street>
                      <city>OrderCity</city>
                      <zip>20000</zip>
                      <country>OrderLand</country>
                    </address>
                  </customer>
                  #{items_xml}
                  <total>#{(i + 1) * 49.95}</total>
                  <status>pending</status>
                </order>
              XML
            end
            orders.join("\n")
          end

          def simple_model_instance(id: 0)
            SimpleModel.new(
              id: id,
              name: "Test Name #{id}",
              active: true,
              score: id + 0.5,
              created_at: Time.new(2024, 1, (id % 28) + 1, 10, 0, 0),
            )
          end

          def person_instance(id: 0)
            Person.new(
              id: id,
              first_name: "John#{id}",
              last_name: "Doe#{id}",
              email: "john#{id}@example.com",
              age: 25 + (id % 50),
              address: Address.new(
                street: "#{id} Main St",
                city: "City#{id}",
                zip: (10000 + id).to_s,
                country: "Country#{id % 10}",
              ),
              phone_numbers: ["555-#{1000 + id}", "555-#{2000 + id}"],
              tags: ["tag#{id % 5}", "tag#{(id + 1) % 5}"],
            )
          end

          def order_instance(id: 0)
            items = 5.times.map do |j|
              OrderItem.new(
                product_id: id * 10 + j,
                quantity: j + 1,
                price: (j + 1) * 9.99,
              )
            end

            Order.new(
              id: id,
              customer: Person.new(
                id: id * 100,
                first_name: "Customer",
                last_name: id.to_s,
                email: "customer#{id}@example.com",
                age: 30,
                address: Address.new(
                  street: "#{id} Order St",
                  city: "OrderCity",
                  zip: "20000",
                  country: "OrderLand",
                ),
              ),
              items: items,
              total: (id + 1) * 49.95,
              status: "pending",
            )
          end
        end
      end

      # Benchmark runner
      class Runner
        def initialize(run_time: 5, warmup: 2)
          @run_time = run_time
          @warmup = warmup
        end

        def run_all
          puts "=" * 80
          puts "Lutaml::Model Comprehensive Performance Benchmarks"
          puts "=" * 80
          puts

          benchmark_model_creation
          benchmark_model_access
          benchmark_xml_parsing
          benchmark_xml_serialization
          benchmark_json_parsing
          benchmark_json_serialization
          benchmark_nested_operations
        end

        private

        def benchmark_model_creation
          puts "-" * 40
          puts "MODEL CREATION BENCHMARK"
          puts "-" * 40

          job = Benchmark::IPS::Job.new
          job.config(time: @run_time, warmup: @warmup)

          job.report("SimpleModel.new") do
            TestModels.simple_model_instance(id: rand(1000))
          end

          job.report("Person.new (nested)") do
            TestModels.person_instance(id: rand(1000))
          end

          job.report("Order.new (deep nested)") do
            TestModels.order_instance(id: rand(100))
          end

          job.run
          puts
        end

        def benchmark_model_access
          puts "-" * 40
          puts "MODEL ACCESS BENCHMARK"
          puts "-" * 40

          simple = TestModels.simple_model_instance
          person = TestModels.person_instance
          order = TestModels.order_instance

          job = Benchmark::IPS::Job.new
          job.config(time: @run_time, warmup: @warmup)

          job.report("SimpleModel getter") do
            simple.name
            simple.id
            simple.active
          end

          job.report("SimpleModel setter") do
            simple.name = "New Name"
            simple.id = 999
            simple.active = false
          end

          job.report("Person nested getter") do
            person.address.city
            person.phone_numbers.first
          end

          job.report("Person nested setter") do
            person.address.city = "New City"
            person.phone_numbers = ["555-0000"]
          end

          job.report("Order deep getter") do
            order.customer.address.street
            order.items.first.price
          end

          job.run
          puts
        end

        def benchmark_xml_parsing
          puts "-" * 40
          puts "XML PARSING BENCHMARK (from_xml)"
          puts "-" * 40

          simple_xml = TestModels.simple_model_xml(count: 1)
          person_xml = TestModels.person_xml(count: 1)
          order_xml = TestModels.order_xml(count: 1)
          person_xml_10 = TestModels.person_xml(count: 10)

          job = Benchmark::IPS::Job.new
          job.config(time: @run_time, warmup: @warmup)

          job.report("SimpleModel.from_xml (1)") do
            TestModels::SimpleModel.from_xml(simple_xml)
          end

          job.report("Person.from_xml (1)") do
            TestModels::Person.from_xml(person_xml)
          end

          job.report("Order.from_xml (1)") do
            TestModels::Order.from_xml(order_xml)
          end

          job.report("Person.from_xml (10)") do
            TestModels::Person.from_xml(person_xml_10)
          end

          job.run
          puts
        end

        def benchmark_xml_serialization
          puts "-" * 40
          puts "XML SERIALIZATION BENCHMARK (to_xml)"
          puts "-" * 40

          simple = TestModels.simple_model_instance
          person = TestModels.person_instance
          order = TestModels.order_instance

          job = Benchmark::IPS::Job.new
          job.config(time: @run_time, warmup: @warmup)

          job.report("SimpleModel.to_xml") do
            simple.to_xml
          end

          job.report("Person.to_xml") do
            person.to_xml
          end

          job.report("Order.to_xml") do
            order.to_xml
          end

          job.run
          puts
        end

        def benchmark_json_parsing
          puts "-" * 40
          puts "JSON PARSING BENCHMARK (from_json)"
          puts "-" * 40

          simple_json = TestModels.simple_model_instance.to_json
          person_json = TestModels.person_instance.to_json

          job = Benchmark::IPS::Job.new
          job.config(time: @run_time, warmup: @warmup)

          job.report("SimpleModel.from_json") do
            TestModels::SimpleModel.from_json(simple_json)
          end

          job.report("Person.from_json") do
            TestModels::Person.from_json(person_json)
          end

          job.run
          puts
        end

        def benchmark_json_serialization
          puts "-" * 40
          puts "JSON SERIALIZATION BENCHMARK (to_json)"
          puts "-" * 40

          simple = TestModels.simple_model_instance
          person = TestModels.person_instance
          order = TestModels.order_instance

          job = Benchmark::IPS::Job.new
          job.config(time: @run_time, warmup: @warmup)

          job.report("SimpleModel.to_json") do
            simple.to_json
          end

          job.report("Person.to_json") do
            person.to_json
          end

          job.report("Order.to_json") do
            order.to_json
          end

          job.run
          puts
        end

        def benchmark_nested_operations
          puts "-" * 40
          puts "NESTED/COLLECTION OPERATIONS BENCHMARK"
          puts "-" * 40

          job = Benchmark::IPS::Job.new
          job.config(time: @run_time, warmup: @warmup)

          # Collection handling
          job.report("Collection (add 10 items)") do
            person = TestModels.person_instance
            10.times { |i| person.tags << "new_tag_#{i}" }
          end

          # Round-trip
          person_xml = TestModels.person_xml(count: 1)
          job.report("Round-trip XML (parse + serialize)") do
            person = TestModels::Person.from_xml(person_xml)
            person.to_xml
          end

          job.run
          puts
        end
      end
    end
  end
end

# Run benchmarks if executed directly
if __FILE__ == $PROGRAM_NAME
  Lutaml::Model::Performance::Runner.new.run_all
end
