
module DeduplicationConcern
  extend ActiveSupport::Concern

  def previous_payloads(events_amount)
    if interpolated['uniqueness_look_back'].present?
      look_back = interpolated['uniqueness_look_back'].to_i
    else
      # Larger of UNIQUENESS_FACTOR * num_events and UNIQUENESS_LOOK_BACK
      uniqueness_look_back = self.class.const_get(:UNIQUENESS_LOOK_BACK) || 0
      factor = self.class.const_get(:UNIQUENESS_FACTOR) || 1
      look_back = events_amount * factor
      if look_back < uniqueness_look_back
        look_back = uniqueness_look_back
      end
    end
    tokens.limit(look_back) if interpolated['mode'] == "on_change"
  end

  # This method returns true if the result should be stored as a new event.
  # If mode is set to 'on_change', this method may return false and update an existing
  # event to expire further in the future.
  def store_payload?(old_events, payload)
    case interpolated['mode'].presence
    when 'on_change'
      token = payload_to_sha(payload)
      if found = old_events.find { |e| e.token == token }
        found.event.update!(expires_at: new_event_expiration_date)
        false
      else
        true
      end
    when 'all', 'merge', ''
      true
    else
      raise "Illegal options[mode]: #{interpolated['mode']}"
    end
  end

  def payload_to_sha(payload)
    Digest::SHA256.hexdigest(payload.to_json)
  end
end
