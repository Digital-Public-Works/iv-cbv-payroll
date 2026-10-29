
# diff calculator for config diffs between environments. Returns object that the admin
# portal uses to display
module AdminApi
  class ConfigDiff
    USAGE_SECTIONS = PartnerConfigLoader::ATTRIBUTE_USAGE_SECTIONS.keys.freeze
    SETTINGS_STRUCTURAL = PartnerConfigLoader::SETTINGS_STRUCTURAL
    CREDENTIALS_STRUCTURAL = PartnerConfigLoader::CREDENTIAL_STRUCTURAL

    # before / after: { settings:, credentials: } (either may be nil). A document
    # missing from `after` isn't compared. `kept` is the loader's kept_secrets.
    def self.call(before, after, kept: Set.new)
      new(before, after, kept).call
    end

    def initialize(before, after, kept)
      @before = before || {}
      @after = after
      @kept = kept
      @deletes = []
    end

    def call
      settings = empty_doc
      credentials = empty_doc

      if @after[:settings]
        b = normalize_settings(@before[:settings])
        a = normalize_settings(@after[:settings])
        settings[:scalars] = diff_scalars(b, a, SETTINGS_STRUCTURAL)
        settings[:application_attributes] = diff_attributes(b["application_attributes"], a["application_attributes"])
        settings[:attribute_usages] = diff_usages(b, a)
        settings[:translations] = diff_translations(b["translations"], a["translations"])
      end

      if @after[:credentials]
        b = normalize_credentials(@before[:credentials])
        a = normalize_credentials(@after[:credentials])
        credentials[:scalars] = diff_scalars(b, a, CREDENTIALS_STRUCTURAL)
        credentials[:transmission_methods] = diff_methods(b["transmission_methods"], a["transmission_methods"])
      end

      { settings: settings, credentials: credentials, deletes: @deletes }
    end

    def self.empty?(diff)
      %i[settings credentials].all? { |doc| diff[doc].values.all?(&:empty?) }
    end

    private

    def empty_doc
      { scalars: [], application_attributes: [], attribute_usages: [], translations: [], transmission_methods: [] }
    end

    def stringify(doc)
      JSON.parse(JSON.generate(doc.to_h))
    end

    # Null and absent are the same; attributes are compared by name, usage lists
    # in order (order is meaningful there), translations by locale and key.
    def normalize_settings(doc)
      src = stringify(doc || {})
      out = src.except(*SETTINGS_STRUCTURAL).compact
      out["application_attributes"] = Array(src["application_attributes"]).map(&:compact).sort_by { |a| a["name"].to_s }
      USAGE_SECTIONS.each do |section|
        out[section] = Array(src[section]).map { |u| { "name" => u["name"].to_s, "required" => !!u["required"] } }
      end
      out["translations"] = (src["translations"] || {}).each_with_object({}) do |(locale, entries), h|
        h[locale.to_s] = (entries || {}).transform_values(&:to_s) if entries.present?
      end
      out
    end

    def normalize_credentials(doc)
      src = stringify(doc || {})
      out = src.except(*CREDENTIALS_STRUCTURAL).compact
      out["transmission_methods"] = Array(src["transmission_methods"]).map do |m|
        {
          "method_type" => m["method_type"].to_s,
          "configs" => Array(m["configs"]).map { |c| { "key" => c["key"].to_s, "value" => c["value"], "encrypted" => !!c["encrypted"] } }
        }
      end
      out
    end

    def diff_scalars(before, after, structural)
      (before.keys | after.keys).sort.filter_map do |key|
        next if structural.include?(key) || before[key] == after[key]
        { key: key, before: before[key], after: after[key] }
      end
    end

    def diff_attributes(before, after)
      b = before.index_by { |a| a["name"] }
      a = after.index_by { |x| x["name"] }
      (b.keys | a.keys).sort.filter_map do |name|
        prev, nxt = b[name], a[name]
        if prev && !nxt
          @deletes << { section: "application_attributes", name: name }
          { name: name, change: "removed", fields: [] }
        elsif nxt && !prev
          { name: name, change: "added", fields: nxt.except("name").sort.map { |k, v| { key: k, before: nil, after: v } } }
        else
          fields = (prev.keys | nxt.keys).sort.reject { |k| prev[k] == nxt[k] }.map { |k| { key: k, before: prev[k], after: nxt[k] } }
          { name: name, change: "changed", fields: fields } if fields.any?
        end
      end
    end

    def diff_usages(before, after)
      USAGE_SECTIONS.filter_map do |section|
        prev, nxt = before[section], after[section]
        next if prev == nxt

        kept = nxt.map { |u| u["name"] }
        prev.each { |u| @deletes << { section: section, name: u["name"] } unless kept.include?(u["name"]) }
        { section: section, before: prev, after: nxt }
      end
    end

    def diff_translations(before, after)
      flat = ->(t) { t.flat_map { |locale, entries| entries.map { |k, v| [ [ locale, k ], v ] } }.to_h }
      b = flat.call(before)
      a = flat.call(after)
      (b.keys | a.keys).sort.filter_map do |(locale, key)|
        prev, nxt = b[[ locale, key ]], a[[ locale, key ]]
        if nxt.nil?
          @deletes << { section: "translations", name: "#{locale}: #{key}" }
          { locale: locale, key: key, change: "removed", before: prev }
        elsif prev.nil?
          { locale: locale, key: key, change: "added", after: nxt }
        elsif prev != nxt
          { locale: locale, key: key, change: "changed", before: prev, after: nxt }
        end
      end
    end

    def diff_methods(before, after)
      b = before.index_by { |m| m["method_type"] }
      a = after.index_by { |m| m["method_type"] }

      (b.keys | a.keys).sort.filter_map do |type|
        prev, nxt = b[type], a[type]
        prev_keys = (prev&.fetch("configs") || []).index_by { |c| c["key"] }
        next_keys = (nxt&.fetch("configs") || []).index_by { |c| c["key"] }

        keys = (prev_keys.keys | next_keys.keys).sort.filter_map do |key|
          p, n = prev_keys[key], next_keys[key]
          secret = !!(p&.fetch("encrypted") || n&.fetch("encrypted"))
          change =
            if p && !n then "removed"
            elsif n && !p then "added"
            elsif @kept.include?([ type, key ]) then nil
            elsif p["encrypted"] != n["encrypted"] || p["value"] != n["value"] then "changed"
            end
          next unless change

          @deletes << { section: "transmission_methods.#{type}", name: key } if change == "removed" && nxt
          entry = { key: key, change: change, secret: secret }
          unless secret
            entry[:before] = p["value"] if p
            entry[:after] = n["value"] if n
          end
          entry
        end

        if prev && !nxt
          @deletes << { section: "transmission_methods", name: type }
          { method_type: type, change: "removed", keys: keys }
        elsif nxt && !prev
          { method_type: type, change: "added", keys: keys }
        elsif keys.any?
          { method_type: type, change: "changed", keys: keys }
        end
      end
    end
  end
end
