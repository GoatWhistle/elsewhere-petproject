class ApplicationController < ActionController::API
  before_action :cors_headers

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from KeyError, ActionController::ParameterMissing, with: :unprocessable

  private

  def payload
    request.request_parameters.deep_stringify_keys
  end

  def cors_headers
    response.set_header("Access-Control-Allow-Origin", "*")
    response.set_header("Access-Control-Allow-Headers", "Content-Type")
  end

  def problem(status, title, detail)
    render json: { type: "about:blank", title: title, status: Rack::Utils.status_code(status), detail: detail }, status: status, content_type: "application/problem+json"
  end

  def not_found(error)
    problem(:not_found, "Not Found", error.message)
  end

  def unprocessable(error)
    problem(:unprocessable_content, "Unprocessable Content", error.message)
  end
end
