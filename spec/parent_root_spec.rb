require_relative "fixtures/sample_model"

RSpec.describe "__parent/__root context" do
  context "XML transform" do
    let(:xml) do
      <<~XML
        <SampleModel>
          <Name>John Doe</Name>
          <Age>25</Age>
          <Balance>0.0</Balance>
          <Tags>
            <Tag>ruby</Tag>
            <Tag>coding</Tag>
          </Tags>
          <Preferences></Preferences>
          <Status>active</Status>
          <LargeNumber>0</LargeNumber>
          <Email>example@example.com</Email>
          <Role>user</Role>
        </SampleModel>
      XML
    end

    it "sets __parent and __root on child model instances" do
      sample = SampleModel.from_xml(xml)

      expect(sample.tags).to all(be_a(SampleModelTag))
      sample.tags.each do |tag|
        expect(tag.__parent).to be(sample)
        expect(tag.__root).to be(sample)
      end
    end
  end

  context "key-value transform (YAML)" do
    let(:yaml) do
      {
        "name" => "John Doe",
        "age" => 25,
        "balance" => "0.0",
        "tags" => [
          { "text" => "ruby" },
          { "text" => "coding" },
        ],
        "preferences" => {},
        "status" => "active",
        "large_number" => 0,
        "email" => "example@example.com",
        "role" => "user",
      }.to_yaml
    end

    it "sets __parent and __root on child model instances" do
      sample = SampleModel.from_yaml(yaml)

      expect(sample.tags).to all(be_a(SampleModelTag))
      sample.tags.each do |tag|
        expect(tag.__parent).to be(sample)
        expect(tag.__root).to be(sample)
      end
    end
  end
end
