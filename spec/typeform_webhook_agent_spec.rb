require 'rails_helper'

describe Agents::WebhookTypeformAgent do
  before do
    @opts = {
      "secret" => "supersecretstring",
      "expected_receive_period_in_days" => 1,
      "payload_path" => "."
    }

    @agent = Agents::TypeformWebhookAgent.new(:name => 'My agent', :options => @opts)
    @agent.user = users(:bob)
    @agent.save!
  end

  describe 'descriptions' do
    it 'has agent description' do
      expect(@agent.description).to_not be_nil
    end

    it 'renders the description markdown without errors' do
      expect { @agent.description }.not_to raise_error
    end

    it 'has event description' do
      expect(@agent.event_description).to_not be_nil
    end
  end

  describe '#working' do
    it 'is not working without having emitted an event' do
      expect(@agent).not_to be_working
    end

    it 'it is working when at least one event was emitted' do
      @event = Event.new
      @event.agent = @agent
      @event.payload = {
        'comment' => 'somevalue'
      }
      @event.save!

      expect(@agent.reload).to be_working
    end

    it 'is not working when there is a recent error' do
      @agent.error 'oh no!'
      expect(@agent.reload).not_to be_working
    end
  end

  it "should have an empty schedule" do
    expect(@agent.schedule).to be_nil
    expect(@agent).to be_valid
    @agent.schedule = "5pm"
    @agent.save!
    expect(@agent.schedule).to be_nil

    @agent.schedule = "5pm"
    expect(@agent).to have(0).errors_on(:schedule)
    expect(@agent.schedule).to be_nil
  end

  it 'cannot receive events' do
    expect(@agent.cannot_receive_events?).to eq true
  end
end
