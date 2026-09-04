#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

def unavailable(classification, reason)
  puts "REVIEWER CAPABILITY REPORT"
  puts "STATUS: UNAVAILABLE"
  puts "CLASSIFICATION: #{classification}"
  puts "REASON: #{reason}"
  exit 1
end

begin
  path = ARGV.fetch(0)
  payload = JSON.parse(File.read(path))
  unavailable("OUTPUT_NOT_CAPTURED", "captured JSON was not an object") unless payload.is_a?(Hash)

  denials = payload.fetch("permission_denials", [])
  unavailable("TOOL_PERMISSION_FAILURE", denials.join("; ")) unless denials.empty?

  models = payload.fetch("modelUsage", {}).keys
  unless models.length == 1 && models.first.include?("fable")
    unavailable("MODEL_UNRESOLVED", "modelUsage did not uniquely prove the fable alias: #{models.join(', ')}")
  end

  result = payload["result"].to_s.strip
  unavailable("OUTPUT_NOT_CAPTURED", "captured JSON contained no reviewer result") if result.empty?
  unavailable("OUTPUT_NOT_CAPTURED", "reviewer result had no consumable VERDICT") unless result.match?(/VERDICT:\s*(ACCEPT|FIX_FIRST|RETHINK)/)

  puts "REVIEWER CAPABILITY REPORT"
  puts "STATUS: AVAILABLE"
  puts "CLASSIFICATION: none"
  puts "REQUESTED_AGENT: fable-advisor"
  puts "REQUESTED_MODEL_ALIAS: fable"
  puts "RESOLVED_MODEL: #{models.join(', ')}"
  puts "TRANSPORT: captured-json"
  puts result
rescue JSON::ParserError => e
  unavailable("OUTPUT_NOT_CAPTURED", "invalid JSON: #{e.message}")
rescue KeyError, Errno::ENOENT => e
  unavailable("OUTPUT_NOT_CAPTURED", e.message)
end
