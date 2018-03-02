require 'rails_helper'

describe Agents::TypeformWebhookAgent do
  before do
    @opts = {
      "access_token" => "BdUAx5RAbAyxx16MiJgUboHTDTKVXNQ93jBjSCihFfMQ",
      "form_id" => "jOyEkB",
      "secret" => "foobar",
      "expected_receive_period_in_days" => 1,
      "payload_path" => "some_key"
    }

    @agent = Agents::TypeformWebhookAgent.new(:name => 'My agent', :options => @opts)
    @agent.user = users(:bob)
    @agent.save!
  end

  let(:payload) { {'people' => [{ 'name' => 'bob' }, { 'name' => 'jon' }] } }

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

    expect(@agent.can_be_scheduled?).to eq false
  end

  it 'cannot receive events' do
    expect(@agent.cannot_receive_events?).to eq true
  end

  describe 'validations' do
    before do
      expect(@agent).to be_valid
    end

    it 'should validate presence of access_token' do
      @agent.options['access_token'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of form_id' do
      @agent.options['form_id'] = ''
      expect(@agent).not_to be_valid
    end
  end

  describe 'receive_web_request' do
    it 'should create event if secret matches' do
      out = nil
      expect {
        out = agent.receive_web_request({ 'secret' => 'foobar', 'some_key' => payload }, "post", "text/html")
      }.to change { Event.count }.by(1)
      expect(out).to eq(['Event Created', 201])
      expect(Event.last.payload).to eq(payload)
    end

    it 'should not create event if secrets do not match' do
      out = nil
      expect {
        out = agent.receive_web_request({ 'secret' => 'bazbat', 'some_key' => payload }, "post", "text/html")
      }.to change { Event.count }.by(0)
      expect(out).to eq(['Not Authorized', 401])
    end

    it 'should respond with `201` if the code option is empty, nil or missing' do
      agent.options['code'] = ''
      out = agent.receive_web_request({ 'secret' => 'foobar', 'some_key' => payload }, "post", "text/html")
      expect(out).to eq(['Event Created', 201])

      agent.options['code'] = nil
      out = agent.receive_web_request({ 'secret' => 'foobar', 'some_key' => payload }, "post", "text/html")
      expect(out).to eq(['Event Created', 201])

      agent.options.delete('code')
      out = agent.receive_web_request({ 'secret' => 'foobar', 'some_key' => payload }, "post", "text/html")
      expect(out).to eq(['Event Created', 201])
    end

    it "should accept POST" do
      out = nil
      expect {
        out = agent.receive_web_request({ 'secret' => 'foobar', 'some_key' => payload }, "post", "text/html")
      }.to change { Event.count }.by(1)
      expect(out).to eq(['Event Created', 201])
    end
  end
end
