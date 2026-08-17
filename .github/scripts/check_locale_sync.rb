require 'yaml'
require 'open3'

require_relative '../../app/services/locale_diff_service'

class LocaleSyncChecker
  I18N_TASKS_CONFIG_PATH = "app/config/i18n-tasks.yml"
  # Locales under i18n-tasks' `ignore_missing` whose keys are intentionally not
  # required in Spanish: `es` (Spanish-specific English-only keys) and `all`
  # (keys allowed missing in every non-base locale). Reusing that list keeps the
  # "English-only" policy declared in exactly one place, so these keys are exempt
  # from the sync check just as they are exempt from i18n-tasks' missing check.
  IGNORE_MISSING_LOCALES = %w[all es].freeze

  def initialize
    @en_locale_path = 'app/config/locales/en.yml'
    @es_locale_path = 'app/config/locales/es.yml'
    @locale_diff_service = LocaleDiffService.new
  end

  def run
    puts "Checking locale synchronization against branch creation point..."

    en_changed_keys, _ = @locale_diff_service.get_changed_keys_in_this_branch("en")
    es_changed_keys, _ = @locale_diff_service.get_changed_keys_in_this_branch("es")

    puts "\n=== English Changed Keys ==="
    puts en_changed_keys.empty? ? "No changes" : en_changed_keys.join(", ")

    puts "\n=== Spanish Changed Keys ==="
    puts es_changed_keys.empty? ? "No changes" : es_changed_keys.join(", ")

    en_changed_keys = en_changed_keys.map { |key| remove_language_prefix(key) }
    es_changed_keys = es_changed_keys.map { |key| remove_language_prefix(key) }

    # Keys declared English-only in i18n-tasks (`ignore_missing`) are exempt from
    # Spanish parity, matching how i18n-tasks and the rest of the app treat them.
    english_only_keys = (en_changed_keys + es_changed_keys).uniq.select { |key| english_only?(key) }
    unless english_only_keys.empty?
      puts "\n=== Skipping keys declared English-only in #{I18N_TASKS_CONFIG_PATH} ==="
      english_only_keys.sort.each { |key| puts "  - #{key}" }
    end

    en_changed_keys = en_changed_keys.reject { |key| english_only?(key) }
    es_changed_keys = es_changed_keys.reject { |key| english_only?(key) }

    if en_changed_keys == es_changed_keys
      puts "\n✅ SUCCESS: English and Spanish locales are synchronized!"
      exit 0
    else
      puts "\n❌ FAILURE: English and Spanish locales are not synchronized!"
      print_synchronization_issues(en_changed_keys, es_changed_keys)
      exit 1
    end
  end

  private

  def english_only?(key)
    english_only_patterns.any? { |pattern| File.fnmatch(pattern, key, File::FNM_EXTGLOB) }
  end

  def english_only_patterns
    @english_only_patterns ||= begin
      config_path = File.join(@locale_diff_service.project_root, I18N_TASKS_CONFIG_PATH)
      config = YAML.load_file(config_path) || {}
      ignore_missing = config["ignore_missing"] || {}
      IGNORE_MISSING_LOCALES.flat_map { |locale| Array(ignore_missing[locale]) }.compact
    end
  end

  def remove_language_prefix(key)
    puts "Normalizing key: #{key}"
    key.sub(/^(en|es)\./, '')
  end

  def print_synchronization_issues(en_changed_keys, es_changed_keys)
    puts "\n=== Synchronization Issues ==="

    missing_in_spanish = en_changed_keys - es_changed_keys
    missing_in_english = es_changed_keys - en_changed_keys

    unless missing_in_spanish.empty?
      puts "\n🔸 Keys changed in English but not in Spanish:"
      missing_in_spanish.each { |key| puts "  - #{key}" }
    end

    unless missing_in_english.empty?
      puts "\n🔸 Keys changed in Spanish but not in English:"
      missing_in_english.each { |key| puts "  - #{key}" }
    end

    puts "\n💡 To fix this, ensure that any changes to English locale keys"
    puts "   are also reflected in the corresponding Spanish locale keys."
  end
end

LocaleSyncChecker.new.run if __FILE__ == $PROGRAM_NAME
