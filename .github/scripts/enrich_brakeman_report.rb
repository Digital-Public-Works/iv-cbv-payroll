#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds CI provenance to a Brakeman JSON report so an archived report is
# self-describing: which commit was scanned, on which ref, by which run.
#
# Brakeman's own scan_info already carries brakeman_version, ruby_version,
# rails_version, start/end timestamps, duration, the list of checks performed,
# and object counts. The fields added here are the ones only GitHub knows.
#
# Usage: enrich_brakeman_report.rb <report.json>

require "json"

path = ARGV[0]
abort "usage: #{$PROGRAM_NAME} <report.json>" if path.nil?
abort "no such report: #{path}" unless File.exist?(path)

report = JSON.parse(File.read(path))
scan_info = report["scan_info"]
abort "report has no scan_info -- is this Brakeman JSON output?" unless scan_info.is_a?(Hash)

server = ENV.fetch("GITHUB_SERVER_URL", "https://github.com")
repository = ENV["GITHUB_REPOSITORY"]
run_id = ENV["GITHUB_RUN_ID"]

run_url =
  if repository && run_id
    "#{server}/#{repository}/actions/runs/#{run_id}"
  end

scan_info["commit_sha"] = ENV["GITHUB_SHA"]
scan_info["ref"] = ENV["GITHUB_REF"]
scan_info["repository"] = repository
scan_info["workflow_run_url"] = run_url
# Re-runs produce a second report for the same SHA; this disambiguates them.
scan_info["run_attempt"] = ENV["GITHUB_RUN_ATTEMPT"]

File.write(path, JSON.pretty_generate(report) + "\n")

puts "Enriched #{path}:"
%w[commit_sha ref repository workflow_run_url run_attempt].each do |key|
  puts "  #{key}=#{scan_info[key].inspect}"
end
