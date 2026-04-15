# frozen_string_literal: true

module UnemploymentSearchDetector
  # Wildcard patterns: any query containing these substrings matches
  WILDCARD_PATTERNS = [ "unemp", "desemp", "department of labor" ].freeze

  # Exact terms: query must match one of these exactly (after strip + downcase)
  EXACT_TERMS = [
    "terminated", "fired", "let go",
    "despedido", "despedida", "despido",
    "terminado", "terminada", "me echaron"
    # TODO: Add agency UI distribution terms once confirmed for AZ & PA
  ].freeze

  def self.match?(query)
    return false if query.blank?

    normalized = query.strip.downcase

    WILDCARD_PATTERNS.any? { |pattern| normalized.include?(pattern) } ||
      EXACT_TERMS.include?(normalized)
  end
end
