# frozen_string_literal: true

module Chattermill
  class ResponseParser

    BASIC_OPTIONS = %w(comment score data_type data_source created_at user_meta segments dataset_id)

    attr_reader :data

    def initialize(data)
      @data = data
    end

    def parse
      outgoing = data.slice(*BASIC_OPTIONS).select { |_, v| v.present? }
      outgoing.merge!(data['extra_fields'].presence || {})
      apply_mappings(outgoing)
      apply_bucketing(outgoing)
    end

    private

    def apply_mappings(payload)
      return payload unless data['mappings'].present?
      data['mappings'].each do |path, values|
        opt = Utils.value_at(payload, path)
        next unless values.has_key?(opt)
        mapped = path.split('.').reverse.each_with_index.inject({}) do |hash, (n,i)|
          new_value = (i == 0 ? values[opt] : hash )
          { n => new_value  }
        end
        payload.deep_merge!(mapped)
      end

      payload
    end

    def apply_bucketing(payload)
      return payload unless data['bucketing'].present?
      data['bucketing'].each do |path, values|
        opt = Utils.value_at(payload, path)
        mapped = path.split('.').reverse.each_with_index.inject({}) do |hash, (n,i)|
          new_value = (i == 0 ? extract_bucket(values,opt) : hash )
          { n => new_value  }
        end
        payload.deep_merge!(mapped)
      end

      payload
    end

    def extract_bucket(hash, value)
      value = value.to_i
      bucket = nil
      hash.each do |k, v|
        range = k.split("-")
        min = range.first
        max = range.last
        if /\+/ =~ max && value >= max.tr("+", "").to_i
          bucket = v
          break
        elsif (min.to_i..max.to_i).cover?(value)
          bucket = v
          break
        end
      end

      bucket
    end

  end
end
