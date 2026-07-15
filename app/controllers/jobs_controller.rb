class JobsController < ApplicationController
  def show
    job = Elsewhere::Store.find_job(params[:id])
    raise ActiveRecord::RecordNotFound, "Job not found" unless job
    render json: job
  end
end
