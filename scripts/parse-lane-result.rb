#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

EXIT_CODES = {
  "complete-candidate" => 0,
  "partial" => 2,
  "refused" => 3,
  "unavailable" => 1
}.freeze

BLOCKING_TOOLS = %w[Read Edit Write].freeze

def protected_state_label(protected_exit)
  case protected_exit
  when 0 then "unchanged"
  when 4 then "violation"
  else "error"
  end
end

def worktree_delta_label(delta_exit)
  case delta_exit
  when 0 then "changed"
  when 3 then "empty"
  else "error"
  end
end

def boundary_events(denials)
  return [0, "none"] unless denials.is_a?(Array)

  names = denials.map { |denial| denial.is_a?(Hash) ? denial["tool_name"].to_s : denial.to_s }
  [names.length, names.empty? ? "none" : names.join(", ")]
end

if ARGV.length != 5
  warn "usage: parse-lane-result.rb JSON_FILE EXPECTED_CANONICAL DELTA_EXIT PROTECTED_EXIT CLAUDE_EXIT"
  exit 1
end

json_path, expected_canonical, delta_exit_raw, protected_exit_raw, claude_exit_raw = ARGV
delta_exit = delta_exit_raw.to_i
protected_exit = protected_exit_raw.to_i
claude_exit = claude_exit_raw.to_i

protected_state = protected_state_label(protected_exit)
worktree_delta = worktree_delta_label(delta_exit)

model_said = ""
cost_usd = "unknown"
num_turns = "unknown"
boundary_count = 0
boundary_summary = "none"

emit = lambda do |status, classification, reason, resolved_model_evidence|
  puts "IMPLEMENTATION REPORT"
  puts "LANE: claude"
  puts "REQUESTED_MODEL: #{expected_canonical}"
  puts "RESOLVED_MODEL_EVIDENCE: #{resolved_model_evidence}"
  puts "STATUS: #{status}"
  puts "CLASSIFICATION: #{classification}"
  puts "REASON: #{reason}"
  puts "COST_USD: #{cost_usd}"
  puts "NUM_TURNS: #{num_turns}"
  puts "BOUNDARY_EVENTS: #{boundary_count} denial(s): #{boundary_summary}"
  puts "PROTECTED_STATE: #{protected_state}"
  puts "WORKTREE_DELTA: #{worktree_delta}"
  puts "MODEL_SAID:"
  puts model_said
  exit(EXIT_CODES.fetch(status))
end

payload = begin
  JSON.parse(File.read(json_path))
rescue JSON::ParserError, Errno::ENOENT, TypeError, ArgumentError, Encoding::CompatibilityError
  nil
end

unless payload.is_a?(Hash)
  emit.call("unavailable", "OUTPUT_NOT_CAPTURED", "captured JSON was not a readable object", "unavailable")
end

model_said = payload["result"].to_s
cost_usd = payload["total_cost_usd"] if payload.key?("total_cost_usd")
num_turns = payload["num_turns"] if payload.key?("num_turns")

raw_denials = payload["permission_denials"]
if raw_denials.is_a?(Array)
  boundary_count, boundary_summary = boundary_events(raw_denials)
end

# Rules 2-4: modelUsage must uniquely and correctly identify the resolved model.
usage = payload["modelUsage"]
unless usage.is_a?(Hash)
  emit.call("unavailable", "MODEL_UNRESOLVED", "modelUsage was missing or not an object", "unavailable")
end

model_keys = usage.keys
if model_keys.empty?
  emit.call("unavailable", "MODEL_UNRESOLVED", "modelUsage had no entries", "unavailable")
elsif model_keys.length > 1
  emit.call("unavailable", "MULTI_MODEL", "modelUsage had #{model_keys.length} entries: #{model_keys.join(', ')}", "unavailable")
end

resolved_model_evidence = model_keys.first
unless resolved_model_evidence == expected_canonical
  emit.call(
    "unavailable", "MODEL_UNRESOLVED",
    "modelUsage resolved #{resolved_model_evidence}, expected #{expected_canonical}",
    resolved_model_evidence
  )
end

# Rules 5-6: the two deterministic guards must have run cleanly.
if protected_exit == 4
  emit.call("refused", "PROTECTED_STATE_VIOLATION", "protected-paths guard reported a violation", resolved_model_evidence)
end

unless [0, 4].include?(protected_exit) && [0, 3].include?(delta_exit)
  emit.call(
    "unavailable", "GUARD_FAILED",
    "worktree-delta or protected-paths guard exited abnormally (delta_exit=#{delta_exit}, protected_exit=#{protected_exit})",
    resolved_model_evidence
  )
end

# Rules 7-8: budget/turn ceilings win over a generic transport failure.
subtype = payload["subtype"]
if subtype == "error_max_budget_usd"
  emit.call("partial", "BUDGET_EXCEEDED", "run stopped after exceeding the configured budget", resolved_model_evidence)
end
if subtype == "error_max_turns"
  emit.call("partial", "TURNS_EXCEEDED", "run stopped after exceeding the configured turn limit", resolved_model_evidence)
end

# Rule 9: any other error or non-zero claude exit is a transport failure.
if payload["is_error"] == true || claude_exit != 0
  emit.call(
    "unavailable", "TRANSPORT_FAILED",
    "claude reported is_error=#{payload['is_error'].inspect} with exit #{claude_exit}",
    resolved_model_evidence
  )
end

# Rule 10: an empty worktree delta is never complete, even on a clean exit.
if delta_exit == 3
  emit.call("refused", "EMPTY_DELTA", "worktree delta was empty; no task changes were made", resolved_model_evidence)
end

# Rule 11: a malformed permission_denials shape cannot be trusted.
if payload.key?("permission_denials") && !payload["permission_denials"].is_a?(Array)
  emit.call("unavailable", "OUTPUT_NOT_CAPTURED", "permission_denials was present but not a list", resolved_model_evidence)
end

# Rule 12: a denied Read/Edit/Write means the spec's file scope was blocked.
denial_list = payload["permission_denials"].is_a?(Array) ? payload["permission_denials"] : []
if denial_list.any? { |denial| denial.is_a?(Hash) && BLOCKING_TOOLS.include?(denial["tool_name"]) }
  emit.call("partial", "TOOL_PERMISSION_FAILURE", "permission_denials blocked a Read/Edit/Write tool call", resolved_model_evidence)
end

# Rule 13: otherwise the run is a complete candidate. Bash-only denials are
# boundary events, never a failure by themselves.
emit.call("complete-candidate", "none", "none", resolved_model_evidence)
