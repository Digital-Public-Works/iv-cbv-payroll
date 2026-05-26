require "rails_helper"

RSpec.describe Transmitters::TransmissionMethodTypes do
  describe ".transmitter_class" do
    Transmitters::TransmissionMethodTypes::METHOD_TYPES.each_key do |method_type|
      it "resolves a transmitter class for #{method_type}" do
        klass = Transmitters::TransmissionMethodTypes.transmitter_class(method_type)
        expect(klass.ancestors).to include(Transmitter)
      end
    end

    it "raises ArgumentError for unknown method types" do
      expect { Transmitters::TransmissionMethodTypes.transmitter_class("smoke_signal") }
        .to raise_error(ArgumentError, /Unsupported transmission method/)
    end
  end
end
