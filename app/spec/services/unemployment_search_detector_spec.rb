require "rails_helper"

RSpec.describe UnemploymentSearchDetector do
  describe ".match?" do
    context "with English wildcard terms" do
      %w[unemployed unemployment UNEMPLOYED Unemployment].each do |term|
        it "matches '#{term}'" do
          expect(described_class.match?(term)).to be true
        end
      end
    end

    context "with English exact terms" do
      ["terminated", "Terminated", "TERMINATED", "fired", "Fired", "let go", "Let Go", "LET GO"].each do |term|
        it "matches '#{term}'" do
          expect(described_class.match?(term)).to be true
        end
      end
    end

    context "with Spanish wildcard terms" do
      %w[desempleado desempleo DESEMPLEADO Desempleo].each do |term|
        it "matches '#{term}'" do
          expect(described_class.match?(term)).to be true
        end
      end
    end

    context "with Spanish exact terms" do
      ["despedido", "Despedida", "DESPIDO", "terminado", "Terminada", "me echaron", "Me Echaron"].each do |term|
        it "matches '#{term}'" do
          expect(described_class.match?(term)).to be true
        end
      end
    end

    context "with non-matching terms" do
      %w[walmart amazon target mcdonalds adp].each do |term|
        it "does not match '#{term}'" do
          expect(described_class.match?(term)).to be false
        end
      end
    end

    context "with edge cases" do
      it "returns false for nil" do
        expect(described_class.match?(nil)).to be false
      end

      it "returns false for blank string" do
        expect(described_class.match?("")).to be false
      end

      it "returns false for whitespace-only string" do
        expect(described_class.match?("   ")).to be false
      end

      it "handles leading/trailing whitespace" do
        expect(described_class.match?("  unemployed  ")).to be true
      end
    end
  end
end
