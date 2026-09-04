#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"

# Minimal protected-local-state guard.
#
# This is deliberately NOT a scan of the ignored tree. It inventories only a
# short, explicit list of local secret/config paths so an implementation or
# evidence lane cannot make verification pass by editing local state that the
# worktree content baseline does not see.
DEFAULT_PATTERNS = [
  ".env",
  ".env.*",
  ".claude/settings.local.json",
  ".codex/",
  ".npmrc"
].freeze

CONFIG_FILE = ".ai-orchestrator-protected-paths"
EXCLUDED_SEGMENTS = %w[.git node_modules].freeze
MAX_INVENTORY = 500

def fail_check(message)
  warn "PROTECTED STATE ERROR: #{message}"
  exit 2
end

def config_patterns(root)
  config = File.join(root, CONFIG_FILE)
  return [] unless File.file?(config)

  # Explicit encoding so the guard behaves identically under a C/POSIX locale.
  File.readlines(config, encoding: "UTF-8").map do |line|
    entry = line.sub(/#.*\z/, "").strip
    next nil if entry.empty?
    fail_check("#{CONFIG_FILE} entry must be repository-relative: #{entry}") if entry.start_with?("/", "~")
    fail_check("#{CONFIG_FILE} entry must not escape the repository: #{entry}") if entry.split("/").include?("..")
    entry
  end.compact
end

def excluded?(relative)
  (relative.split("/") & EXCLUDED_SEGMENTS).any?
end

def expand(root, patterns)
  paths = patterns.flat_map do |pattern|
    if pattern.end_with?("/")
      directory = pattern.chomp("/")
      [directory] + Dir.glob("#{directory}/**/*", File::FNM_DOTMATCH, base: root)
    else
      Dir.glob(pattern, File::FNM_DOTMATCH, base: root)
    end
  end

  paths = paths.reject { |relative| relative.empty? || relative.end_with?("/.", "/..") || excluded?(relative) }
  paths = paths.select { |relative| File.exist?(File.join(root, relative)) || File.symlink?(File.join(root, relative)) }
  paths.uniq.sort
end

def describe(root, relative)
  absolute = File.join(root, relative)
  if File.symlink?(absolute)
    { "type" => "symlink", "target" => File.readlink(absolute) }
  elsif File.directory?(absolute)
    { "type" => "directory" }
  elsif File.file?(absolute)
    stat = File.stat(absolute)
    { "type" => "file", "mode" => stat.mode & 0o777, "sha256" => Digest::SHA256.file(absolute).hexdigest }
  else
    { "type" => "other" }
  end
end

def collect_state(root, patterns)
  relatives = expand(root, patterns)
  if relatives.length > MAX_INVENTORY
    fail_check(
      "protected inventory of #{relatives.length} paths exceeds the #{MAX_INVENTORY} limit; " \
      "narrow #{CONFIG_FILE} instead of protecting a whole tree"
    )
  end

  relatives.to_h { |relative| [relative, describe(root, relative)] }
end

begin
  command, state_path, root_arg = ARGV
  unless %w[snapshot check].include?(command) && state_path
    fail_check("usage: protected-paths.rb <snapshot|check> STATE_FILE [ROOT]")
  end

  root = File.expand_path(root_arg || Dir.pwd)
  state_path = File.expand_path(state_path)
  root_prefix = root.end_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}"
  fail_check("state file must be outside the protected root") if state_path.start_with?(root_prefix)

  case command
  when "snapshot"
    patterns = (DEFAULT_PATTERNS + config_patterns(root)).uniq
    state = collect_state(root, patterns)
    File.write(state_path, JSON.generate({ "root" => root, "patterns" => patterns, "files" => state }))
    puts "PROTECTED STATE BASELINE"
    puts "STATUS: captured"
    puts "PATTERNS: #{patterns.length}"
    puts "FILES: #{state.length}"
  when "check"
    baseline = JSON.parse(File.read(state_path, encoding: "UTF-8"))
    fail_check("baseline root does not match current root") unless baseline["root"] == root

    # Fail closed: a task that removes a configured pattern cannot shrink the
    # guard. The checked set is the union of baseline and current patterns.
    patterns = (baseline.fetch("patterns") | config_patterns(root)).uniq
    before = baseline.fetch("files")
    after = collect_state(root, patterns)

    violations = (before.keys | after.keys).sort.map do |relative|
      next if before[relative] == after[relative]
      kind = if !before.key?(relative)
               "added"
             elsif !after.key?(relative)
               "deleted"
             else
               "modified"
             end
      "#{kind}: #{relative}"
    end.compact

    puts "PROTECTED STATE REPORT"
    puts "PATTERNS: #{patterns.length}"
    puts "FILES: #{after.length}"
    if violations.empty?
      puts "STATUS: unchanged"
      puts "VIOLATIONS: none"
    else
      puts "STATUS: violation"
      violations.each { |violation| puts "VIOLATION: #{violation}" }
      exit 4
    end
  end
rescue JSON::ParserError, Errno::ENOENT, Errno::EACCES => e
  fail_check(e.message)
end
