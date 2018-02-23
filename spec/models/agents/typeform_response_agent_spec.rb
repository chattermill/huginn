require 'rails_helper'

describe Agents::TypeformResponseAgent, :vcr do
  before do
    VCR.insert_cassette 'typeforms/response', record: :new_episodes

    @opts = {
      "access_token": "HVKFmp3ooW5gYMjCEUij6MSJjtXL4KSW4FWucRMLkjUr",
      "form_id": "D7aM1F",
      'expected_update_period_in_days' => '1',
      'mode' => 'on_change',
      'guess_mode' => true,
      'limit' => 2,
      'offset' => 0,
      'mapping_object' => '{}',
      'bucketing_object' => '{}'
    }

    @agent = Agents::TypeformResponseAgent.new(:name => 'My agent', :options => @opts)
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

    it 'should validate presence of access_token' do
      @agent.options['access_token'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of form_id' do
      @agent.options['form_id'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate expected_update_period_in_days is greater than 0' do
      @agent.options['expected_update_period_in_days'] = 0
      expect(@agent).not_to be_valid
    end

    it 'should validate uniqueness_look_back greater than 0' do
      @agent.options['uniqueness_look_back'] = 0
      expect(@agent).not_to be_valid
    end

    it 'should validate since date format' do
      @agent.options['since'] = '2 hours ago'
      expect(@agent).to be_valid

      @agent.options['since'] = '10-20-2018'
      expect(@agent).to be_valid

      @agent.options['since'] = 'xxx'
      expect(@agent).not_to be_valid
    end

  end

  describe '#chek' do
    context 'when there is not another agent running' do
      it 'emits events' do
        expect { @agent.check }.to change { Event.count }.by(2)
      end

      it 'does not emit duplicated events ' do
        @agent.check
        @agent.events.last.destroy

        expect { @agent.check }.to change { Event.count }.by(1)
        expect(@agent.events.count).to eq(2)
      end

      it 'emits correct payload' do
        @agent.check
        payload = @agent.events.last.payload
        expected = {
          'score' => '9',
          'comment' => 'Porque aveces cuando solicitas el servicio se tardan mucho en llegar ',
          'created_at' => '',
          'id' => 1,
          'answers' => '',
          'formatted_answers' => '',
          'metadata' => '',
          'hidden_variables' => '',
          'mapped_variables' => ''
        }

        expect(payload).to eq(expected)
      end

      context 'with limit param' do
        it 'emits limited events' do
          @agent.options['limit'] = 3
          expect { @agent.check }.to change { Event.count }.by(3)
        end
      end

      it 'changes memory in_process to true while running' do
        @agent.check
        expect(@agent.reload.memory['in_process']).to be true
      end

      it 'changes memory in_process to false after running' do
        @agent.check
        @agent.save!
        expect(@agent.reload.memory['in_process']).to be false
      end
    end

    context 'when there is another agent running' do
      it 'does not emit events' do
        @agent.memory['in_process'] = true
        expect { @agent.check }.to change { Event.count }.by(0)
      end
    end
  end

  describe 'helpers' do
  end
end
