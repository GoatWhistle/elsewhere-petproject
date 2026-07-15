class GenerateFuturesJob < ApplicationJob
  queue_as :default

  def perform(session_id, job_id)
    result = Planning::Futures.generate(session_id: session_id)
    Elsewhere::Store.complete_job(job_id, result)
  rescue StandardError => error
    Elsewhere::Store.fail_job(job_id, error)
    raise
  end
end
