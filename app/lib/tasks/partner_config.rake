namespace :partner_config do
  desc "Validate a partner YAML config (dry-run). Usage: rake partner_config:validate[partner_id,source]"
  task :validate, [ :partner_id, :source ] => :environment do |_t, args|
    partner_id = args.fetch(:partner_id) { abort "Usage: rake partner:validate[partner_id,source]" }
    source = args.fetch(:source) { abort "Usage: rake partner:validate[partner_id,source]" }

    loader = PartnerConfigLoader.new(source)
    loader.load!
    loader.validate!

    if loader.data[:partner_id] != partner_id
      abort "ERROR: partner_id in file (#{loader.data[:partner_id]}) does not match argument (#{partner_id})"
    end

    display_errors(partner_id, loader)

    if loader.valid?
      puts "Validation passed for #{partner_id}."
    else
      abort "Validation FAILED for #{partner_id}."
    end
  rescue PartnerConfigLoader::SourceError => e
    abort "Source error: #{e.message}"
  end

  desc "Apply a partner YAML config to the database. Usage: rake partner_config:apply[partner_id,source]"
  task :apply, [ :partner_id, :source ] => :environment do |_t, args|
    partner_id = args.fetch(:partner_id) { abort "Usage: rake partner:apply[partner_id,source]" }
    source = args.fetch(:source) { abort "Usage: rake partner:apply[partner_id,source]" }

    loader = PartnerConfigLoader.new(source)
    loader.load!
    loader.validate!

    display_errors(partner_id, loader)

    unless loader.valid? && loader.data[:partner_id] == partner_id
      abort "Cannot apply invalid config for #{partner_id}."
    end

    changes = loader.apply!
    print_apply_summary(partner_id, changes)
  rescue PartnerConfigLoader::SourceError => e
    abort "Source error: #{e.message}"
  rescue PartnerConfigLoader::ValidationError => e
    abort e.message
  end

  desc "Export a partner's DB config to YAML on stdout. Usage: rake partner_config:export[partner_id]"
  task :export, [ :partner_id ] => :environment do |_t, args|
    partner_id = args.fetch(:partner_id) { abort "Usage: rake partner:export[partner_id]" }

    data = PartnerConfigLoader.export(partner_id)
    puts data.to_yaml
  rescue ActiveRecord::RecordNotFound
    abort "Partner '#{partner_id}' not found in database."
  end
end

def display_errors(partner_id, loader)
  if loader.data[:partner_id] != partner_id
    puts "ERROR: partner_id in file (#{loader.data[:partner_id]}) does not match argument (#{partner_id})"
  end

  if loader.warnings.any?
    puts "WARNINGS:"
    loader.warnings.each { |w| puts "  - #{w}" }
  end

  if loader.errors.any?
    puts "ERRORS:"
    loader.errors.each { |e| puts "  - #{e}" }
  end
end

def print_apply_summary(partner_id, changes)
  puts "\n=== Applied #{partner_id} ==="
  puts "  Config: #{changes[:config]}"

  [ :transmission_methods, :application_attributes, :translations ].each do |section|
    c = changes[section]
    puts "  #{section}: #{c[:created]} created, #{c[:updated]} updated, #{c[:deleted]} deleted"
  end
end
