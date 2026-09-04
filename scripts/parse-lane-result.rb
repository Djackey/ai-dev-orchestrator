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
STDERR_EXCERPT_BYTES = 300

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

# Reads up to STDERR_EXCERPT_BYTES of a captured stderr file so REASON can
# carry the actual error text instead of just an exit code.
def read_excerpt(path)
  return "" if path.nil? || path.empty? || !File.file?(path)

  begin
    File.open(path, "rb") { |f| f.read(STDERR_EXCERPT_BYTES) }.to_s.strip
  rescue StandardError
    ""
  end
end

# worktree-delta.rb 'check' prints one "CHANGE: <kind>: <path>" line per
# changed path; this extracts just the paths.
def parse_changed_paths(path)
  return [] if path.nil? || path.empty? || !File.file?(path)

  content = begin
    File.read(path, encoding: "utf-8")
  rescue StandardError
    ""
  end

  content.each_line.map do |line|
    match = line.chomp.match(/\ACHANGE: (?:added|deleted|modified): (.+)\z/)
    match && match[1]
  end.compact
end

# fnmatch semantics without FNM_PATHNAME, so both '*' and '**' match across
# '/' — the spec requires this for '**' and does not forbid it for '*'.
def path_allowed?(path, globs)
  globs.any? { |glob| File.fnmatch(glob, path) }
end

def scope_report(allow_path_globs, changed_paths)
  if allow_path_globs.empty?
    return { text: "unchecked (no --allow-path given)", violation: false }
  end

  offenders = changed_paths.reject { |path| path_allowed?(path, allow_path_globs) }
  if offenders.empty?
    { text: "ok (#{changed_paths.length} changed paths within #{allow_path_globs.length} allowed globs)", violation: false }
  else
    shown = offenders.first(10)
    suffix = offenders.length > 10 ? " (+#{offenders.length - 10} more)" : ""
    { text: "changed path(s) outside allowed scope: #{shown.join(', ')}#{suffix}", violation: true }
  end
end

if ARGV.length < 9
  warn "usage: parse-lane-result.rb JSON_FILE EXPECTED_CANONICAL ALIAS DELTA_EXIT PROTECTED_EXIT CLAUDE_EXIT ERROR_FILE GUARD_ERROR_FILE DELTA_STDOUT_FILE [ALLOW_PATH_GLOB]..."
  exit 1
end

json_path, expected_canonical, alias_name, delta_exit_raw, protected_exit_raw, claude_exit_raw,
  error_file, guard_error_file, delta_stdout_file = ARGV[0, 9]
allow_path_globs = ARGV[9..] || []

delta_exit = delta_exit_raw.to_i
protected_exit = protected_exit_raw.to_i
claude_exit = claude_exit_raw.to_i

map_generated_at = ENV["CLAUDE_LANE_MAP_GENERATED_AT"]
map_generated_at = "unknown" if map_generated_at.nil? || map_generated_at.empty?
map_claude_version = ENV["CLAUDE_LANE_MAP_CLAUDE_VERSION"]
map_claude_version = "unknown" if map_claude_version.nil? || map_claude_version.empty?

protected_state = protected_state_label(protected_exit)
worktree_delta = worktree_delta_label(delta_exit)

model_said = ""
cost_usd = "unknown"
num_turns = "unknown"
boundary_count = 0
boundary_summary = "none"
scope_text = "unchecked (no --allow-path given)"

emit = lambda do |status, classification, reason, resolved_model_evidence|
  puts "IMPLEMENTATION REPORT"
  puts "LANE: claude"
  puts "REQUESTED_ALIAS: #{alias_name}"
  puts "EXPECTED_CANONICAL: #{expected_canonical} (model map #{map_generated_at}, claude #{map_claude_version})"
  puts "RESOLVED_MODEL_EVIDENCE: #{resolved_model_evidence}"
  puts "STATUS: #{status}"
  puts "CLASSIFICATION: #{classification}"
  puts "REASON: #{reason}"
  puts "COST_USD: #{cost_usd}"
  puts "NUM_TURNS: #{num_turns}"
  puts "BOUNDARY_EVENTS: #{boundary_count} denial(s): #{boundary_summary}"
  puts "PROTECTED_STATE: #{protected_state}"
  puts "WORKTREE_DELTA: #{worktree_delta}"
  puts "SCOPE: #{scope_text}"
  puts "MODEL_SAID:"
  puts model_said
  exit(EXIT_CODES.fetch(status))
end

# Rule 1: the protected-paths guard exit is independent of the captured JSON
# and wins even when that JSON is missing or malformed.
if protected_exit == 4
  emit.call("refused", "PROTECTED_STATE_VIOLATION", "protected-paths guard reported a violation", "unavailable")
end

# Rule 2: either guard exiting outside its own contract cannot be trusted,
# regardless of what the captured JSON says.
unless [0, 4].include?(protected_exit) && [0, 3].include?(delta_exit)
  excerpt = read_excerpt(guard_error_file)
  reason = "worktree-delta or protected-paths guard exited abnormally (delta_exit=#{delta_exit}, protected_exit=#{protected_exit})"
  reason += ": #{excerpt}" unless excerpt.empty?
  emit.call("unavailable", "GUARD_FAILED", reason, "unavailable")
end

changed_paths = parse_changed_paths(delta_stdout_file)
scope = scope_report(allow_path_globs, changed_paths)
scope_text = scope[:text]

payload = begin
  JSON.parse(File.read(json_path, encoding: "utf-8"))
rescue JSON::ParserError, Errno::ENOENT, TypeError, ArgumentError, Encoding::CompatibilityError, EncodingError
  nil
end

unless payload.is_a?(Hash)
  # Rule 3: an unreadable payload alongside a non-zero claude exit is a
  # transport failure, not merely uncaptured output — the process itself
  # did not complete.
  if claude_exit != 0
    excerpt = read_excerpt(error_file)
    reason = "claude exited #{claude_exit} with unreadable output"
    reason += ": #{excerpt}" unless excerpt.empty?
    emit.call("unavailable", "TRANSPORT_FAILED", reason, "unavailable")
  end
  # Rule 4: a clean exit with unreadable output is a capture defect.
  emit.call("unavailable", "OUTPUT_NOT_CAPTURED", "captured JSON was not a readable object", "unavailable")
end

model_said = payload["result"].to_s
cost_usd = payload["total_cost_usd"] if payload.key?("total_cost_usd")
num_turns = payload["num_turns"] if payload.key?("num_turns")

raw_denials = payload["permission_denials"]
if raw_denials.is_a?(Array)
  boundary_count, boundary_summary = boundary_events(raw_denials)
end

# Rules 5-8: modelUsage must uniquely and correctly identify the resolved model.
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

# Rules 9-10: budget/turn ceilings win over a generic transport failure.
subtype = payload["subtype"]
if subtype == "error_max_budget_usd"
  emit.call("partial", "BUDGET_EXCEEDED", "run stopped after exceeding the configured budget", resolved_model_evidence)
end
if subtype == "error_max_turns"
  emit.call("partial", "TURNS_EXCEEDED", "run stopped after exceeding the configured turn limit", resolved_model_evidence)
end

# Rule 11: any other error or non-zero claude exit is a transport failure.
if payload["is_error"] == true || claude_exit != 0
  excerpt = read_excerpt(error_file)
  reason = "claude reported is_error=#{payload['is_error'].inspect} with exit #{claude_exit}"
  reason += ": #{excerpt}" unless excerpt.empty?
  emit.call("unavailable", "TRANSPORT_FAILED", reason, resolved_model_evidence)
end

# Rule 12: an empty worktree delta is never complete, even on a clean exit.
if delta_exit == 3
  emit.call("refused", "EMPTY_DELTA", "worktree delta was empty; no task changes were made", resolved_model_evidence)
end

# Rule 13: a declared --allow-path scope excludes any changed path outside it.
if scope[:violation]
  emit.call("refused", "SCOPE_VIOLATION", scope[:text], resolved_model_evidence)
end

# Rule 14: a malformed permission_denials shape (not an array, or an entry
# that is not an object with a string tool_name) cannot be trusted.
if payload.key?("permission_denials")
  denials = payload["permission_denials"]
  malformed = !denials.is_a?(Array) || denials.any? { |d| !d.is_a?(Hash) || !d["tool_name"].is_a?(String) }
  if malformed
    emit.call("unavailable", "OUTPUT_NOT_CAPTURED", "permission_denials contained a malformed entry", resolved_model_evidence)
  end
end

# Rule 15: a denied Read/Edit/Write means the spec's file scope was blocked.
denial_list = payload["permission_denials"].is_a?(Array) ? payload["permission_denials"] : []
if denial_list.any? { |denial| denial.is_a?(Hash) && BLOCKING_TOOLS.include?(denial["tool_name"]) }
  emit.call("partial", "TOOL_PERMISSION_FAILURE", "permission_denials blocked a Read/Edit/Write tool call", resolved_model_evidence)
end

# Rule 16: otherwise the run is a complete candidate. Bash-only denials are
# boundary events, never a failure by themselves.
emit.call("complete-candidate", "none", "none", resolved_model_evidence)
