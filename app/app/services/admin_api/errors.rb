# Errors the admin API turns into responses (see Api::Admin::V1::BaseController).
module AdminApi::Errors
  class Base < StandardError
    def status = :unprocessable_content
    def body = { message: message }
  end

  # 422 with the loader's structured errors and warnings.
  class Invalid < Base
    def initialize(loader, message: nil)
      @loader = loader
      super(message || loader.error_details.first&.dig(:message) || "Invalid config")
    end

    def body
      { message: message, errors: @loader.error_details, warnings: @loader.warning_details }
    end
  end

  # 422 for a malformed request (bad JSON, a section of the wrong type, ...).
  class BadRequest < Base
    def body = { message: message, errors: [ { message: message } ] }
  end

  # 422: the change would delete config and the caller didn't confirm it.
  class UnconfirmedDeletes < Base
    def initialize(deletes)
      @deletes = deletes
      super("This change deletes config; confirm the deletes to apply it")
    end

    def body = { message: message, deletes: @deletes }
  end

  # 403: the environment's write policy refuses the change
  class Forbidden < Base
    def status = :forbidden
  end

  # 409: the partner changed since the caller read it
  class Conflict < Base
    def status = :conflict
  end
end
