require "securerandom"

module Elsewhere
  class Store
    class << self
      attr_reader :sessions, :futures, :jobs

      def reset!
        @sessions = {}
        @futures = {}
        @jobs = {}
      end

      def id; SecureRandom.uuid; end

      def job(kind, result)
        job = { "id" => id, "status" => "succeeded", "kind" => kind, "created_at" => Time.now.utc.iso8601, "result" => result, "error" => nil }
        jobs[job["id"]] = job
        job
      end
    end
    reset!
  end
end

