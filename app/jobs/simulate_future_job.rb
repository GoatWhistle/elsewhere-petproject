class SimulateFutureJob < ApplicationJob
  queue_as :default

  def perform(future_id, job_id, payload)
    result = Planning::Simulator.simulate(future_id: future_id, adjustments: payload["adjustments"], instruction: payload["instruction"], persist_to_dna: payload["persist_to_travel_dna"])
    Elsewhere::Store.complete_job(job_id, result)
  rescue StandardError => error
    Elsewhere::Store.fail_job(job_id, error)
    raise
  end
end
