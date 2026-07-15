class SimulationsController < ApplicationController
  def create
    job = Elsewhere::Store.queued_job("simulate")
    SimulateFutureJob.perform_later(params[:id], job.fetch("id"), payload)
    render json: Elsewhere::Store.find_job(job.fetch("id")), status: :accepted
  end
end
