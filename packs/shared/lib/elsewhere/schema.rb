# frozen_string_literal: true

require "json"

module Elsewhere
  # A small JSON Schema validator, deliberately not a gem. `AI::Task` uses it to refuse malformed model output
  # and the contract spec uses it to refuse responses that drifted from `docs/04_api/openapi.yaml`: both are
  # JSON that has to match a declared shape. Supports what the contract uses — $ref, allOf, oneOf, union types,
  # object required/properties/additionalProperties, array items/minItems, enum.
  module Schema
    class Invalid < StandardError; end

    module_function

    # `root` is the document that `$ref` pointers resolve against; omit it for self-contained schemas.
    def validate!(value, schema, root: nil, path: "$")
      return value if schema.nil? || schema == true

      schema = resolve(schema, root)

      validate_composites!(value, schema, root, path)
      validate_type!(value, schema, path)
      validate_enum!(value, schema, path)
      validate_object!(value, schema, root, path) if value.is_a?(Hash)
      validate_array!(value, schema, root, path) if value.is_a?(Array)

      value
    end

    def valid?(value, schema, root: nil)
      validate!(value, schema, root: root)
      true
    rescue Invalid
      false
    end

    def resolve(schema, root)
      return schema unless schema.is_a?(Hash) && schema["$ref"]
      raise Invalid, "cannot resolve #{schema["$ref"]} without a root document" unless root

      pointer = schema["$ref"].delete_prefix("#/").split("/")
      resolved = pointer.reduce(root) { |node, key| node.fetch(key) { raise Invalid, "unknown $ref #{schema["$ref"]}" } }
      resolve(resolved, root)
    end

    def validate_composites!(value, schema, root, path)
      Array(schema["allOf"]).each { |member| validate!(value, member, root: root, path: path) }

      alternatives = schema["oneOf"] || schema["anyOf"]
      return unless alternatives

      # Each branch's reason: a bare "matches no alternative" sends the reader hunting.
      failures = []
      alternatives.each do |member|
        return value if valid?(value, member, root: root)
      end
      alternatives.each do |member|
        validate!(value, member, root: root, path: path)
      rescue Invalid => error
        failures << error.message
      end

      raise Invalid, "#{path}: matches none of the declared alternatives — #{failures.uniq.join(" | ")}"
    end

    def validate_type!(value, schema, path)
      types = Array(schema["type"])
      return if types.empty?
      return if types.any? { |type| matches_type?(value, type) }

      raise Invalid, "#{path}: expected #{types.join(" or ")}, got #{value.class}"
    end

    def matches_type?(value, type)
      case type
      when "object" then value.is_a?(Hash)
      when "array" then value.is_a?(Array)
      when "string" then value.is_a?(String)
      when "integer" then value.is_a?(Integer)
      when "number" then value.is_a?(Numeric)
      when "boolean" then value == true || value == false
      when "null" then value.nil?
      else true
      end
    end

    def validate_enum!(value, schema, path)
      return unless schema["enum"]
      return if schema["enum"].include?(value)

      raise Invalid, "#{path}: #{value.inspect} is outside the closed vocabulary #{schema["enum"].inspect}"
    end

    def validate_object!(value, schema, root, path)
      properties = schema["properties"] || {}

      Array(schema["required"]).each do |key|
        raise Invalid, "#{path}: missing required property #{key.inspect}" unless value.key?(key)
      end

      if schema["additionalProperties"] == false
        unknown = value.keys - properties.keys
        raise Invalid, "#{path}: unknown properties #{unknown.inspect}" if unknown.any?
      end

      properties.each do |key, child|
        next unless value.key?(key)

        validate!(value[key], child, root: root, path: "#{path}.#{key}")
      end
    end

    def validate_array!(value, schema, root, path)
      if schema["minItems"] && value.size < schema["minItems"]
        raise Invalid, "#{path}: expected at least #{schema["minItems"]} items, got #{value.size}"
      end

      return unless schema["items"]

      value.each_with_index { |item, index| validate!(item, schema["items"], root: root, path: "#{path}[#{index}]") }
    end
  end
end
