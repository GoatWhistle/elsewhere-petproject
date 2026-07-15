class MitigationsController < ApplicationController
  def create
    adjustment = Foresight::Forecasts.mitigation_adjustment(risk_id: params[:risk_id], mitigation_id: params[:mitigation_id])
    job = Elsewhere::Store.queued_job("apply_mitigation")
    SimulateFutureJob.perform_later(params[:future_id], job.fetch("id"), { "adjustments" => [adjustment] })
    render json: Elsewhere::Store.find_job(job.fetch("id")), status: :accepted
  end
end
