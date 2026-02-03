module Warnable
  extend ActiveSupport::Concern

  included do
    before_validation :clear_warnings
  end

  def warnings
    @warnings ||= ActiveModel::Errors.new(self)
  end

  def has_warnings?
    warnings.any?
  end

  private

  def clear_warnings
    warnings.clear
  end
end
