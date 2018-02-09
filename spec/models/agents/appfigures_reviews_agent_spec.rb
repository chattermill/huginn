require 'rails_helper'

describe Agents::AppfiguresReviewsAgent, :vcr do
  before do
    VCR.insert_cassette 'appfigures', record: :new_episodes

    @opts = {
      'filter' => 'count=2',
      'client_key' => '5696c786d30d4b7788fdc35cd886e852',
      'basic_auth' => 'mikhail@chattermill.io:94YUecNW>fKPuq',
      'products' => '41013601294',
      'expected_update_period_in_days' => '1',
      'mode' => 'on_change'
    }
    @agent = Agents::AppfiguresReviewsAgent.new(:name => 'My agent', :options => @opts)
    @agent.user = users(:bob)
    @agent.save!
  end

  after do
    VCR.eject_cassette
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

  describe 'validations' do
    before do
      expect(@agent).to be_valid
    end

    it 'should validate presence of client_key' do
      @agent.options['client_key'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of basic_auth' do
      @agent.options['basic_auth'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of expected_update_period_in_days' do
      @agent.options['expected_update_period_in_days'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate expected_update_period_in_daysis greater than 0' do
      @agent.options['expected_update_period_in_days'] = 0
      expect(@agent).not_to be_valid
    end

    it 'should validate mode value' do
      @agent.options['mode'] = 'xx'
      expect(@agent).not_to be_valid
    end

    it 'should validate uniqueness_look_back greater than 0' do
      @agent.options['uniqueness_look_back'] = 0
      expect(@agent).not_to be_valid
    end
  end
end
