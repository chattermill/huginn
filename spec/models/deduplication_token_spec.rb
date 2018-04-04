require 'rails_helper'

describe DeduplicationToken do
  describe "validations" do
    before do
      event = events(:bob_website_agent_event)
      event.save!

      @token = DeduplicationToken.new(:agent => agents(:jane_website_agent), :token => "a402f13618854bc6538f38c6a9f05eff64af6b20f41cfa9e3267691035769539", event: event)
      expect(@token).to be_valid
    end

    it "requires an agent" do
      @token.agent = nil
      expect(@token).not_to be_valid
      expect(@token).to have(2).error_on(:agent)
    end

    it "requires an event" do
      @token.event = nil
      expect(@token).not_to be_valid
      expect(@token).to have(2).error_on(:event)
    end

    it "requires a token" do
      @token.token = ""
      expect(@token).not_to be_valid
      expect(@token).to have(1).error_on(:token)
    end
  end

  describe "#expired" do
    it "return tokens created with more than 3 months" do
      agents(:jane_rain_notifier_agent).create_event(payload: {"hi": "there"})
      event = agents(:jane_rain_notifier_agent).create_event(payload: {"hello": "there"})

      DeduplicationToken.last.update!(created_at: 3.months.ago)

      expect(DeduplicationToken.expired.count).to eq(1)
      expect(DeduplicationToken.expired.first.event_id).to eq(event.id)
    end
  end

  describe "#cleanup_expired" do
    it "destroy all expired tokens" do
      event1 = agents(:jane_rain_notifier_agent).create_event(payload: {"hi": "there"})
      event2 = agents(:jane_rain_notifier_agent).create_event(payload: {"hello": "there"})
      DeduplicationToken.last.update!(created_at: 3.months.ago)

      expect(DeduplicationToken.count).to eq(2)

      DeduplicationToken.cleanup_expired!
      
      expect(DeduplicationToken.count).to eq(1)
      expect(DeduplicationToken.first.id).to eq(event1.token.id)
    end
  end
end
