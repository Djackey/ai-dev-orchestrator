#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

def fail_validation(message)
  warn "FAIL: #{message}"
  exit 1
end

def frontmatter(path)
  source = File.read(path)
  match = source.match(/\A---\n(.*?)\n---\n/m)
  fail_validation("#{path} has no complete YAML frontmatter") unless match

  data = YAML.safe_load(match[1], permitted_classes: [], aliases: false)
  fail_validation("#{path} frontmatter is not a mapping") unless data.is_a?(Hash)
  data
rescue Psych::SyntaxError => e
  fail_validation("#{path} invalid YAML: #{e.message}")
end

agent_paths = Dir["agents/*.md"].sort
fail_validation("no agents found") if agent_paths.empty?

names = agent_paths.map do |path|
  data = frontmatter(path)
  %w[name description model tools].each do |key|
    fail_validation("#{path} missing #{key}") unless data.key?(key)
  end

  expected_name = File.basename(path, ".md")
  fail_validation("#{path} name does not match filename") unless data["name"] == expected_name
  fail_validation("#{path} description is empty") unless data["description"].is_a?(String) && !data["description"].empty?
  fail_validation("#{path} model is empty") unless data["model"].is_a?(String) && !data["model"].empty?

  tools = data["tools"].is_a?(Array) ? data["tools"] : data["tools"].to_s.split(",").map(&:strip)
  fail_validation("#{path} tools are empty") if tools.empty?
  if expected_name == "evidence-explorer" && (tools & %w[Write Edit]).any?
    fail_validation("#{path} exposes Write/Edit")
  end

  data["name"]
end

fail_validation("duplicate agent names") unless names.uniq.length == names.length

skill_path = "skills/orchestration/SKILL.md"
skill = frontmatter(skill_path)
%w[name description].each do |key|
  fail_validation("#{skill_path} missing #{key}") unless skill[key].is_a?(String) && !skill[key].empty?
end
fail_validation("#{skill_path} name does not match directory") unless skill["name"] == "orchestration"

puts "PASS: YAML frontmatter for #{agent_paths.length} agents and orchestration skill"
