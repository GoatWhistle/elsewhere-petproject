require_relative "taxonomy"

module Planning
  # Travel DNA in PostgreSQL, versioned (DEC-023). Two rules, both because the user is the authority on their
  # own preferences: `PATCH` is an upsert by dimension and never a whole-set replace, and nothing cascades —
  # clearing `car_free` marks the element inferred from it rather than quietly re-weighting `walkability`.
  module DnaStore
    # What an element becomes when its basis is taken away: not deleted, but no longer claiming to rest on
    # anything.
    ORPHANED_PROVENANCE = "default".freeze
    ORPHANED_CONFIDENCE = 0.3

    module_function

    def create(session_id:, dna:)
      version = TravelDnaVersionRecord.create!(
        session_id: session_id, version: next_version(session_id), parent_id: latest(session_id)&.id,
        unmatched_intent: Array(dna["unmatched_intent"]), degraded: !!dna["_degraded"],
        degraded_reason: dna["_degraded_reason"]&.to_s
      )
      write_elements(version, dna["elements"])
      read(version)
    end

    # The upsert. Incoming elements land on their dimension and nothing else is touched.
    def update(session_id:, elements:)
      current = latest(session_id)
      raise ArgumentError, "no Travel DNA for session #{session_id}" unless current

      merged = merge(read(current)["elements"], elements)
      version = TravelDnaVersionRecord.create!(
        session_id: session_id, version: current.version + 1, parent_id: current.id,
        unmatched_intent: current.unmatched_intent, degraded: current.degraded,
        degraded_reason: current.degraded_reason
      )
      write_elements(version, merged)
      read(version)
    end

    def merge(existing, incoming)
      by_dimension = existing.to_h { |element| [element["dimension"], element.dup] }

      Array(incoming).each do |raw|
        dimension = raw["dimension"] || raw[:dimension]
        next unless Taxonomy.known?(dimension)

        previous = by_dimension[dimension] || {}
        by_dimension[dimension] = previous.merge(
          "dimension" => dimension,
          "kind" => raw["kind"] || raw[:kind] || previous["kind"] || Taxonomy.kind(dimension),
          "target" => raw.key?("target") || raw.key?(:target) ? (raw["target"] || raw[:target]) : previous["target"],
          "weight" => raw.key?("weight") || raw.key?(:weight) ? (raw["weight"] || raw[:weight]) : previous["weight"],
          # An edit is confirmed at full confidence, and nothing inferred may overwrite it afterwards.
          "provenance" => "confirmed", "confidence" => 1.0,
          # An edited element stands on the user's word now, not on whatever it was derived from.
          "_derived_from" => nil
        )
      end

      mark_orphans(by_dimension.values)
    end

    # An inference whose basis is gone is shown, never silently repaired or deleted.
    def mark_orphans(elements)
      by_dimension = elements.to_h { |element| [element["dimension"], element] }

      elements.map do |element|
        source = element["_derived_from"]
        next element unless source

        basis = by_dimension[source]
        next element if basis && !cleared?(basis)

        element.merge("provenance" => ORPHANED_PROVENANCE, "confidence" => ORPHANED_CONFIDENCE)
      end
    end

    def cleared?(element)
      target = element["target"]
      target.nil? || target == false
    end

    def write_elements(version, elements)
      Array(elements).each_with_index do |element, index|
        TravelDnaElementRecord.create!(
          travel_dna_version_id: version.id, dimension: element["dimension"],
          kind: element["kind"] || Taxonomy.kind(element["dimension"]),
          target: { "value" => element["target"] }, weight: element["weight"],
          tolerance: element["tolerance"], provenance: element["provenance"] || "inferred",
          confidence: element["confidence"] || 0.3, position: index,
          derived_from: element["_derived_from"]
        )
      end
    end

    def read(version)
      version = TravelDnaVersionRecord.find(version.id) if version.is_a?(TravelDnaVersionRecord)
      {
        "id" => version.id, "version" => version.version,
        "elements" => version.elements.map { |record| element_hash(record) },
        "unmatched_intent" => version.unmatched_intent,
        "_degraded" => version.degraded, "_degraded_reason" => version.degraded_reason
      }
    end

    def element_hash(record)
      {
        "dimension" => record.dimension, "kind" => record.kind,
        "target" => record.target.is_a?(Hash) ? record.target["value"] : record.target,
        "weight" => record.weight&.to_f, "tolerance" => record.tolerance&.to_f,
        "provenance" => record.provenance, "confidence" => record.confidence.to_f
      }.tap { |hash| hash["_derived_from"] = record.derived_from if record.derived_from }
    end

    def latest(session_id)
      TravelDnaVersionRecord.where(session_id: session_id).order(version: :desc).first
    end

    def find(session_id) = latest(session_id)&.then { |version| read(version) }

    def next_version(session_id) = (latest(session_id)&.version || 0) + 1
  end
end
