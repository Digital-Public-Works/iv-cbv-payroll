namespace :partner_config do
  desc "Validate a partner's settings + credentials YAML (dry-run). Usage: rake partner_config:validate[partner_id,settings_source,credentials_source]"
  task :validate, [ :partner_id, :settings_source, :credentials_source ] => :environment do |t, args|
    partner_id, settings_source, credentials_source = fetch_partner_config_args(t, args)

    loader = PartnerConfigLoader.new(settings_source, credentials_source)
    loader.load!
    loader.validate!

    if loader.yaml_data[:partner_id] != partner_id
      abort "ERROR: partner_id in files (#{loader.yaml_data[:partner_id]}) does not match argument (#{partner_id})"
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

  desc "Apply a partner's settings + credentials YAML to the database. Usage: rake partner_config:apply[partner_id,settings_source,credentials_source]"
  task :apply, [ :partner_id, :settings_source, :credentials_source ] => :environment do |t, args|
    partner_id, settings_source, credentials_source = fetch_partner_config_args(t, args)

    loader = PartnerConfigLoader.new(settings_source, credentials_source)
    loader.load!
    loader.validate!

    display_errors(partner_id, loader)

    unless loader.valid? && loader.yaml_data[:partner_id] == partner_id
      abort "Cannot apply invalid config for #{partner_id}."
    end

    changes = loader.apply!
    print_apply_summary(partner_id, changes, loader)
  rescue PartnerConfigLoader::SourceError => e
    abort "Source error: #{e.message}"
  rescue PartnerConfigLoader::ValidationError => e
    abort e.message
  end

  desc "Export a partner's DB config to settings + credentials YAML. Usage: rake partner_config:export[partner_id,out_dir]"
  task :export, [ :partner_id, :out_dir ] => :environment do |_t, args|
    partner_id = args.fetch(:partner_id) { abort "Usage: rake partner_config:export[partner_id,out_dir]" }

    data = PartnerConfigLoader.export(partner_id)
    settings_name = "#{partner_id}.settings.yml"
    credentials_name = "#{partner_id}.credentials.#{Rails.env}.yml"
    out_dir = args[:out_dir]

    if out_dir.present?
      settings_path = File.join(out_dir, settings_name)
      credentials_path = File.join(out_dir, credentials_name)
      File.write(settings_path, data[:settings].to_yaml)
      File.write(credentials_path, data[:credentials].to_yaml)
      puts "Wrote #{settings_path}"
      puts "Wrote #{credentials_path}"
      puts "NOTE: encrypted secrets in the credentials file are masked as " \
        "#{PartnerConfigLoader::MASKED_PLACEHOLDER}; replace them before applying."
    else
      puts "# ===== #{settings_name} ====="
      puts data[:settings].to_yaml
      puts "# ===== #{credentials_name} ====="
      puts data[:credentials].to_yaml
    end
  rescue ActiveRecord::RecordNotFound
    abort "Partner '#{partner_id}' not found in database."
  end
end

def fetch_partner_config_args(task, args)
  usage = "Usage: rake #{task.name}[partner_id,settings_source,credentials_source]"
  partner_id = args.fetch(:partner_id) { abort usage }
  settings_source = args.fetch(:settings_source) { abort usage }
  credentials_source = args.fetch(:credentials_source) { abort usage }
  [ partner_id, settings_source, credentials_source ]
end

def display_errors(partner_id, loader)
  if loader.yaml_data[:partner_id] != partner_id
    puts "ERROR: partner_id in files (#{loader.yaml_data[:partner_id]}) does not match argument (#{partner_id})"
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

def print_apply_summary(partner_id, changes, loader)
  puts "\n=== Applied #{partner_id} ==="
  puts "  Config: #{changes[:config]}"

  # Echo the argyle environment so an operator can eyeball that the right
  # credentials document was applied (e.g. "yes, this is prod"). Transmission
  # config values are intentionally not printed: they can contain secrets, and
  # the key set changes over time (another thing to keep in sync).
  puts "  argyle_environment (verify this is correct!): #{loader.yaml_data[:argyle_environment]}"

  [ :transmission_methods, :application_attributes, :translations ].each do |section|
    c = changes[section]
    puts "  #{section}: #{c[:created]} created, #{c[:updated]} updated, #{c[:deleted]} deleted"
  end
end
