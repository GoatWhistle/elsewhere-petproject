require "securerandom"
require "time"

module Elsewhere
  class Store
    class << self
      def reset!
        @sessions = {}
        @futures = {}
        @jobs = {}
        [JobRecord, FutureVersionRecord, PlanningSessionRecord].each(&:delete_all) if persistent?
      end

      def id; SecureRandom.uuid; end

      def save_session(payload)
        if persistent?
          PlanningSessionRecord.upsert({ id: payload.fetch("id"), payload: payload, created_at: Time.current, updated_at: Time.current }, unique_by: :id)
        else
          sessions[payload.fetch("id")] = payload
        end
        payload
      end

      def find_session(id)
        persistent? ? PlanningSessionRecord.find_by(id: id)&.payload : sessions[id]
      end

      def save_future(payload)
        if persistent?
          FutureVersionRecord.upsert({ id: payload.fetch("id"), session_id: payload.fetch("session_id"), lineage_id: payload.fetch("lineage_id"), parent_id: payload["parent_id"], version: payload.fetch("version"), payload: payload, created_at: Time.current, updated_at: Time.current }, unique_by: :id)
        else
          futures[payload.fetch("id")] = payload
        end
        payload
      end

      def find_future(id)
        persistent? ? FutureVersionRecord.find_by(id: id)&.payload : futures[id]
      end

      # Removing a superseded drag intermediate. Not an update: a Future is never mutated in place, and the
      # pixels of a dragged slider are simply not kept (DEC-025).
      def delete_future(id)
        persistent? ? FutureVersionRecord.where(id: id).delete_all : futures.delete(id)
      end

      def futures_for_session(session_id)
        persistent? ? FutureVersionRecord.where(session_id: session_id).order(:created_at).map(&:payload) : futures.values.select { |future| future["session_id"] == session_id }
      end

      def queued_job(kind)
        save_job({ "id" => id, "status" => "queued", "kind" => kind, "created_at" => now, "result" => nil, "error" => nil })
      end

      def job(kind, result)
        save_job({ "id" => id, "status" => "succeeded", "kind" => kind, "created_at" => now, "result" => result, "error" => nil })
      end

      def complete_job(id, result)
        payload = find_job(id) || { "id" => id, "kind" => "generate_futures", "created_at" => now }
        save_job(payload.merge("status" => "succeeded", "result" => result, "error" => nil))
      end

      def fail_job(id, error)
        payload = find_job(id) || { "id" => id, "kind" => "generate_futures", "created_at" => now }
        save_job(payload.merge("status" => "failed", "result" => nil, "error" => { "detail" => error.message }))
      end

      def find_job(id)
        persistent? ? JobRecord.find_by(id: id)&.payload : jobs[id]
      end

      private

      def save_job(payload)
        if persistent?
          JobRecord.upsert({ id: payload.fetch("id"), kind: payload.fetch("kind"), status: payload.fetch("status"), payload: payload, created_at: Time.current, updated_at: Time.current }, unique_by: :id)
        else
          jobs[payload.fetch("id")] = payload
        end
        payload
      end

      def persistent?
        defined?(ActiveRecord::Base) && ActiveRecord::Base.connected? && defined?(PlanningSessionRecord) && PlanningSessionRecord.table_exists?
      rescue StandardError
        false
      end

      def sessions; @sessions ||= {}; end
      def futures; @futures ||= {}; end
      def jobs; @jobs ||= {}; end
      def now; Time.now.utc.iso8601; end
    end
  end
end
