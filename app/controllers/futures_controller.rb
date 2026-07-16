class FuturesController < ApplicationController
  def create
    job = Elsewhere::Store.queued_job("generate_futures")
    GenerateFuturesJob.perform_later(params[:id], job.fetch("id"))
    render json: Elsewhere::Store.find_job(job.fetch("id")), status: :accepted
  end

  def index
    render json: { futures: Planning::Futures.list(session_id: params[:id]).map { |future| Planning::Futures.public(future) }, diversity_note: nil }
  end

  def show
    future = Planning::Futures.find(future_id: params[:id])
    raise ActiveRecord::RecordNotFound, "Future not found" unless future
    render json: Planning::Futures.public(future)
  end
end
