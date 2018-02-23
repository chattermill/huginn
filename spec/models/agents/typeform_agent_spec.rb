require 'rails_helper'

describe Agents::TypeformAgent, :vcr do
  before do
    VCR.insert_cassette 'typeforms/typeform', record: :new_episodes, serialize_with: :json

    @opts = {
      "api_key": "41820b9f2eda8d5dea56808ca8172652a888460f",
      "form_id": "uOSkwS",
      'expected_update_period_in_days' => '1',
      'mode' => 'on_change',
      'guess_mode' => true,
      'limit' => 3,
      'offset' => 0
    }

    @agent = Agents::TypeformAgent.new(:name => 'My agent', :options => @opts)
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

    it 'should validate presence of api_key' do
      @agent.options['api_key'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of form_id' do
      @agent.options['form_id'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate expected_update_period_in_daysis greater than 0' do
      @agent.options['expected_update_period_in_days'] = 0
      expect(@agent).not_to be_valid
    end




    it 'should validate uniqueness_look_back greater than 0' do
      @agent.options['uniqueness_look_back'] = 0
      expect(@agent).not_to be_valid
    end
  end

  describe '#chek' do
    context 'when there is not another agent running' do
      it 'emits events' do
        expect { @agent.check }.to change { Event.count }.by(3)
      end

      it 'does not emit duplicated events ' do
        @agent.check
        @agent.events.last.destroy

        expect { @agent.check }.to change { Event.count }.by(1)
        expect(@agent.events.count).to eq(3)
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
          'metadata' => '',
          'hidden_variables' => ''
        }

        expect(payload).to eq(expected)
      end

      context 'with limit param' do
        it 'emits limited events' do
          @agent.options['limit'] = 5
          expect { @agent.check }.to change { Event.count }.by(5)
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
    it 'build a correct params string' do
      expected = "order_by[]=date_submit,desc&limit=3&offset=0"
      expect(@agent.send(:params)).to eq(expected)

      @agent.options['limit'] = ''
      expected = 'order_by[]=date_submit,desc&offset=0'
      expect(@agent.send(:params)).to eq(expected)

      @agent.options['offset'] = ''
      expected = 'order_by[]=date_submit,desc&limit=3'
      expect(@agent.send(:params)).to eq(expected)
    end
  end
end
