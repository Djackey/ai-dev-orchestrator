#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

VERDICTS = %w[ACCEPT FIX_FIRST RETHINK].freeze

# A verdict is only consumable when it stands alone on its own line. Prose,
# blockquotes, inline code, emphasis, and schema templates such as
# "VERDICT: ACCEPT | FIX_FIRST | RETHINK" deliberately do not match.
VERDICT_LINE = /\A[[:space:]]*VERDICT:[[:blank:]]*(#{VERDICTS.join('|')})[[:space:]]*\z/.freeze

def unavailable(classification, reason)
  puts "REVIEWER CAPABILITY REPORT"
  puts "STATUS: UNAVAILABLE"
  puts "CLASSIFICATION: #{classification}"
  puts "REASON: #{reason}"
  exit 1
end

def extract_verdict(result)
  matches = result.lines.map { |line| VERDICT_LINE.match(line) }.compact.map { |match| match[1] }

  if matches.empty?
    unavailable(
      "OUTPUT_NOT_CAPTURED",
      "reviewer result contained no standalone `VERDICT: #{VERDICTS.join(' | ')}` line"
    )
  end

  unless matches.length == 1
    unavailable(
      "VERDICT_AMBIGUOUS",
      "reviewer result contained #{matches.length} standalone verdict lines: #{matches.join(', ')}"
    )
  end

  matches.first
end

begin
  path = ARGV.fetch(0)
  payload = JSON.parse(File.read(path))
  unavailable("OUTPUT_NOT_CAPTURED", "captured JSON was not an object") unless payload.is_a?(Hash)

  # An absent permission_denials field is tolerated for older CLI payloads, but a
  # present-and-malformed one (JSON null, a string, an object) is not silently
  # read as "no denials".
  denials = payload.key?("permission_denials") ? payload["permission_denials"] : []
  unless denials.is_a?(Array)
    unavailable("OUTPUT_NOT_CAPTURED", "permission_denials was present but not a list: #{denials.inspect}")
  end
  unavailable("TOOL_PERMISSION_FAILURE", denials.join("; ")) unless denials.empty?

  usage = payload["modelUsage"] || {}
  unavailable("MODEL_UNRESOLVED", "modelUsage was not an object") unless usage.is_a?(Hash)
  models = usage.keys
  unless models.length == 1 && models.first.to_s.include?("fable")
    unavailable("MODEL_UNRESOLVED", "modelUsage did not uniquely prove the fable alias: #{models.join(', ')}")
  end

  result = payload["result"].to_s.strip
  unavailable("OUTPUT_NOT_CAPTURED", "captured JSON contained no reviewer result") if result.empty?
  verdict = extract_verdict(result)

  puts "REVIEWER CAPABILITY REPORT"
  puts "STATUS: AVAILABLE"
  puts "CLASSIFICATION: none"
  puts "REQUESTED_AGENT: ai-dev-orchestrator:fable-advisor"
  puts "REQUESTED_MODEL_ALIAS: fable"
  puts "RESOLVED_MODEL: #{models.join(', ')}"
  puts "TRANSPORT: captured-json"
  puts "PARSED_VERDICT: #{verdict}"
  puts result
rescue JSON::ParserError => e
  unavailable("OUTPUT_NOT_CAPTURED", "invalid JSON: #{e.message}")
rescue KeyError, Errno::ENOENT, NoMethodError, TypeError => e
  unavailable("OUTPUT_NOT_CAPTURED", "#{e.class}: #{e.message}")
end
