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
end
