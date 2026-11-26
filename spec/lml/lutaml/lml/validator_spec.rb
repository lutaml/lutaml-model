# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Lutaml::Lml::Validator do
  def violations_for(src)
    document = Lutaml::Lml.parse_document(StringIO.new(src))
    described_class.violations(document)
  end

  describe 'class constraints' do
    it 'flags duplicate type names' do
      violations = violations_for(<<~LML)
        models M {
          class Tile { }
          class Tile { }
        }
      LML
      expect(violations.map(&:rule)).to eq(['unique_names'])
      expect(violations.first.message).to include('Tile')
    end

    it 'flags duplicate attribute names within a class' do
      violations = violations_for(<<~LML)
        models M {
          class Tile {
            attribute size, String
            attribute size, String
          }
        }
      LML
      expect(violations.map(&:rule)).to eq(['unique_attribute_names'])
      expect(violations.first.message).to include('"size"')
    end
  end

  describe 'attribute constraints' do
    it 'flags a missing mandatory attribute on an instance' do
      violations = violations_for(<<~LML)
        models M {
          class Product {
            attribute code, String { cardinality 1 }
          }
        }
        instances {
          Product "p1" {
            label = "x"
          }
        }
      LML
      expect(violations.map(&:rule))
        .to contain_exactly('mandatory_attributes', 'unknown_attributes')
      mandatory = violations.find { |v| v.rule == 'mandatory_attributes' }
      expect(mandatory.message).to include("'p1'")
      expect(mandatory.message).to include("'code'")
    end

    it 'accepts a populated mandatory attribute' do
      violations = violations_for(<<~LML)
        models M {
          class Product {
            attribute code, String { cardinality 1 }
          }
        }
        instances {
          Product "p1" {
            code = "ABC"
          }
        }
      LML
      expect(violations).to be_empty
    end

    it 'accepts values matching the declared type' do
      violations = violations_for(<<~LML)
        models M {
          class Product {
            attribute count, Integer
          }
        }
        instances {
          Product "p1" {
            count = 42
          }
        }
      LML
      expect(violations).to be_empty
    end

    it 'flags a non-numeric value for an Integer attribute' do
      violations = violations_for(<<~LML)
        models M {
          class Product {
            attribute count, Integer
          }
        }
        instances {
          Product "p1" {
            count = "many"
          }
        }
      LML
      expect(violations.map(&:rule)).to eq(['type_conformity'])
    end
  end

  describe 'reference validity' do
    it 'flags references to unknown instances' do
      violations = violations_for(<<~LML)
        instances {
          Product "p1" {
            other = reference:(Missing.x)
          }
        }
      LML
      expect(violations.map(&:rule)).to eq(['reference_validity'])
      expect(violations.first.message).to include("'Missing.x'")
    end

    it 'flags circular references' do
      violations = violations_for(<<~LML)
        instances {
          Product "a" {
            next = reference:(b)
          }
          Product "b" {
            next = reference:(a)
          }
        }
      LML
      expect(violations.map(&:rule)).to include('reference_circularity')
    end

    it 'accepts resolvable references' do
      violations = violations_for(<<~LML)
        instances {
          Product "a" {
            part = reference:(b.code)
          }
          Product "b" {
            code = "B1"
          }
        }
      LML
      expect(violations).to be_empty
    end
  end

  describe 'values sets' do
    it 'accepts membership for values-set attributes' do
      violations = violations_for(<<~LML)
        models M {
          class Tile {
            attribute status, String { values { draft, published } }
          }
        }
        instances {
          Tile "t" {
            status = "draft"
          }
        }
      LML
      expect(violations).to be_empty
    end

    it 'flags a value outside the declared set' do
      violations = violations_for(<<~LML)
        models M {
          class Tile {
            attribute status, String { values { draft, published } }
          }
        }
        instances {
          Tile "t" {
            status = "archived"
          }
        }
      LML
      expect(violations.map(&:rule)).to eq(['values_set_membership'])
      expect(violations.first.message).to include('archived')
    end
  end

  describe 'unknown instance attributes' do
    it 'flags attributes absent from the class definition' do
      violations = violations_for(<<~LML)
        models M {
          class Product {
            attribute code, String
          }
        }
        instances {
          Product "p1" {
            code = "A"
            mystery = "x"
          }
        }
      LML
      expect(violations.map(&:rule)).to eq(['unknown_attributes'])
      expect(violations.first.message).to include("'mystery'")
    end
  end

  describe 'package-scoped uniqueness' do
    it 'allows the same name in sibling packages' do
      violations = violations_for(<<~LML)
        package Ceramics {
          class Tile { }
        }
        package Textiles {
          class Tile { }
        }
      LML
      expect(violations).to be_empty
    end

    it 'flags duplicates within one package' do
      violations = violations_for(<<~LML)
        package Ceramics {
          class Tile { }
          class Tile { }
        }
      LML
      expect(violations.map(&:rule)).to eq(['unique_names'])
      expect(violations.first.message).to include("package 'Ceramics'")
    end

    it 'flags duplicates between a package and the document root' do
      violations = violations_for(<<~LML)
        class Tile { }
        package Ceramics {
          class Tile { }
        }
      LML
      expect(violations).to be_empty
    end
  end
end
