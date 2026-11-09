desc "Run brakeman with potential non-0 return code"
task :brakeman do
  # -z flag makes it return non-0 if there are any warnings
  # -q quiets output
  unless system("brakeman -z -q") # system is true if return is 0, false otherwise
    abort("Brakeman detected one or more code problems, please run it manually and inspect the output.")
  end
end

namespace :bundler do
  require "bundler/audit/cli"

  desc "Updates the ruby-advisory-db and runs audit"
  task :audit do
    %w[update check].each do |command|
      Bundler::Audit::CLI.start [ command ]
    end
  end
rescue LoadError
  # no-op, probably in a production environment
end

# Severity at or above which npm audit findings fail the build. The command flag
# and the helper's filter are both derived from this one value.
NPM_AUDIT_LEVEL = "high".freeze
NPM_AUDIT_BLOCKING = %w[info low moderate high critical]
  .drop_while { |severity| severity != NPM_AUDIT_LEVEL }.freeze

namespace :npm do
  desc "Run npm audit"
  task :audit do
    require "open3"
    require "json"
    # --audit-level makes npm exit non-zero only at or above this severity.
    stdout, stderr, status = Open3.capture3("npm audit --json --audit-level=#{NPM_AUDIT_LEVEL}")
    parsed = JSON.parse(stdout)
    puts "Vulnerability counts: #{parsed.dig("metadata", "vulnerabilities")}"
    unless status.success?
      warn stderr
      puts JSON.pretty_generate(parsed)
      if /503 Service Unavailable/.match?(stderr)
        puts "Ignoring unavailable server"
      elsif all_issues_ignored?(parsed)
        puts "Ignoring known and accepted npm audit results"
      else
        warn "Failed with exit code #{status.exitstatus}"
        exit status.exitstatus
      end
    end
  end
end

def all_issues_ignored?(report)
  # npm exits non-zero only at or above --audit-level, but the report lists every
  # severity, so only consider the ones that can fail the build.
  present_advisories = report.fetch("vulnerabilities", {})
    .select { |_name, data| NPM_AUDIT_BLOCKING.include?(data["severity"]) }
    .keys.sort

  # Package names to be ignored, and a comment as to why we're ignoring
  ignored_advisories = [
    # "some-package", # high - only used at build time
  ].sort

  pp "Present advisories: #{present_advisories}"
  pp "Ignored advisories: #{ignored_advisories}"
  (present_advisories - ignored_advisories).empty?
end

task default: [ "standard", "brakeman", "bundler:audit", "npm:audit" ]
