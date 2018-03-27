require 'rails_helper'

describe Agents::DelightedAgent do
  before do

    @opts = {
      "api_key": "token123",
      "page": 1,
      "per_page": "3",
      "mode": "on_change",
      "expected_update_period_in_days": "1"
    }
    @agent = Agents::DelightedAgent.new(:name => 'My agent', :options => @opts)
    @agent.user = users(:bob)
    @agent.save!

    stub_request(:get, /api.delightedapp.com\/v1\/survey_responses/).to_return(
      body: File.read(Rails.root.join("spec/data_fixtures/delighted/survey_responses.json")),
      headers: {"Content-Type"=> "application/json"},
      status: 200)
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
  end

  describe '#check' do
    it 'emits events' do
      expect { @agent.check }.to change { Event.count }.by(3)
    end

    it 'does not emit duplicated events ' do
      @agent.check
      @agent.events.last.destroy

      expect { @agent.check }.to change { Event.count }.by(1)
      expect(@agent.events.count).to eq(3)
      expect(@agent.tokens.count).to eq(3)
    end

    it 'emits correct payload' do
      @agent.check
      expected = {
        "survey_type" => "nps",
        "score" => 10,
        "comment" => nil,
        "permalink" => "https://delighted.com/r/cYnHR7xwKWyEB",
        "created_at" => 1519050765,
        "updated_at" => 1519050765,
        "person_properties" => {
            "segment" => "140",
            "country" => "France",
            "brand" => "Allo Resto",
            "restaurant_key" => "955411",
            "restaurant_id" => "9554",
            "restaurant_name" => "Allo Pizza Pasta",
            "cuisine" => "burger",
            "city" => "STRASBOURG - MONTAGNE VERTE",
            "owner_name" => nil,
            "locale" => "fr-justeat",
            "delighted intro message" => "Nous aimerions vous poser une question. Je vous remercie",
            "delighted email subject" => "Recommanderais tu Allo Resto?"
        },
        "notes" => [],
        "tags" => [],
        "person" =>  "153585695",
        "id" => "50942642"
      }

      expect(@agent.events.first.payload).to eq(expected)
    end
  end

  describe 'helpers' do
    describe 'store_payload' do
      it 'returns true when mode is all or merge' do
        @agent.options['mode'] = 'all'
        expect(@agent.send(:store_payload?, [], 'key: 123')).to be true

        @agent.options['mode'] = 'merge'
        expect(@agent.send(:store_payload?, [], 'key: 123')).to be true
      end

      it 'raises an expception when mode is invalid' do
        @agent.options['mode'] = 'xyz'
        expect {
          @agent.send(:store_payload?, [], 'key: 123')
        }.to raise_error('Illegal options[mode]: xyz')
      end

      context 'when mode is on_change' do
        before do
          @event = Event.new
          @event.agent = @agent
          @event.payload = {
            'comment' => 'somevalue'
          }
          @event.save!
        end

        it 'returns false if events exist' do
          expect(@agent.send(:store_payload?, @agent.tokens, 'comment' => 'somevalue')).to be false
        end

        it 'returns true if events does not exist' do
          expect(@agent.send(:store_payload?, @agent.tokens, 'comment' => 'othervalue')).to be true
        end
      end
    end

    describe 'previous_payloads' do
      before do
        Event.create payload: { 'comment' => 'some value'}, agent: @agent
        Event.create payload: { 'comment' => 'another value'}, agent: @agent
        Event.create payload: { 'comment' => 'other comment'}, agent: @agent

        @uniqueness_look_back = 1
        @uniqueness_factor = 1
      end

      context 'when uniqueness_look_back is present' do
        before do
          @agent.options['uniqueness_look_back'] = 2
        end

        it 'returns a list of old events limited by uniqueness_look_back' do
          expect(@agent.events.count).to eq(3)
          expect(@agent.send(:previous_payloads, 1 * @uniqueness_factor, @uniqueness_look_back).count).to eq(2)
        end
      end

      context 'when uniqueness_look_back is not present' do
        it 'returns a list of old events limited by received events' do
          expect(@agent.events.count).to eq(3)
          expect(@agent.send(:previous_payloads, 3 * @uniqueness_factor, @uniqueness_look_back).count).to eq(3)
        end
      end

      it 'returns nil when mode is not on_change' do
        @agent.options['mode'] = 'all'
        expect(@agent.send(:previous_payloads, 1 * @uniqueness_factor, @uniqueness_look_back)).to be nil
      end
    end

    describe 'default_query' do
      it 'generates a correct default_query' do
        @agent.options['page'] = '3'
        @agent.options['per_page'] = '5'

        expected = {
          order: 'desc',
          page: '3',
          per_page: '5',
          expand: ['person']
        }

        expect(@agent.send(:default_query)).to eq(expected)
      end
    end
  end

end
