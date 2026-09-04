#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"

def fail_check(message)
  warn "WORKTREE DELTA ERROR: #{message}"
  exit 2
end

def collect_state(root)
  stdout, stderr, status = Open3.capture3(
    "git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"
  )
  fail_check("git ls-files failed: #{stderr}") unless status.success?

  stdout.split("\0").reject(&:empty?).sort.to_h do |relative|
    absolute = File.join(root, relative)
    value = if File.symlink?(absolute)
              { "type" => "symlink", "target" => File.readlink(absolute) }
            elsif File.file?(absolute)
              stat = File.stat(absolute)
              {
                "type" => "file",
                "mode" => stat.mode & 0o777,
                "sha256" => Digest::SHA256.file(absolute).hexdigest
              }
            else
              { "type" => "missing" }
            end
    [relative, value]
  end
end

begin
  command, state_path, root_arg = ARGV
  fail_check("usage: worktree-delta.rb <snapshot|check> STATE_FILE [ROOT]") unless %w[snapshot check].include?(command) && state_path

  root = File.expand_path(root_arg || Dir.pwd)
  state_path = File.expand_path(state_path)
  root_prefix = root.end_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}"
  fail_check("state file must be outside the worktree") if state_path.start_with?(root_prefix)

  case command
  when "snapshot"
    state = collect_state(root)
    File.write(state_path, JSON.generate({ "root" => root, "files" => state }))
    puts "WORKTREE BASELINE"
    puts "STATUS: captured"
    puts "FILES: #{state.length}"
  when "check"
    baseline = JSON.parse(File.read(state_path))
    fail_check("baseline root does not match current root") unless baseline["root"] == root
    before = baseline.fetch("files")
    after = collect_state(root)
    paths = (before.keys | after.keys).sort
    changes = paths.map do |path|
      next if before[path] == after[path]
      kind = if !before.key?(path)
               "added"
             elsif !after.key?(path) || after[path]["type"] == "missing"
               "deleted"
             else
               "modified"
             end
      "#{kind}: #{path}"
    end.compact

    puts "WORKTREE DELTA REPORT"
    if changes.empty?
      puts "STATUS: empty"
      puts "CHANGES: none"
      exit 3
    end

    puts "STATUS: changed"
    changes.each { |change| puts "CHANGE: #{change}" }
  end
rescue JSON::ParserError, Errno::ENOENT => e
  fail_check(e.message)
end
