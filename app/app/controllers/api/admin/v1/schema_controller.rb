class Api::Admin::V1::SchemaController < Api::Admin::V1::BaseController
  def show
    render json: AdminApi::Schema.call
  end
end
