require 'rails_helper'

describe Agents::AppfiguresReviewsAgent, :vcr do
  before do
    VCR.insert_cassette 'appfigures', record: :none

    @opts = {
      'filter' => 'count=2',
      'client_key' => 'token123',
      'basic_auth' => 'user:pass',
      'products' => '41013601294',
      'expected_update_period_in_days' => '1',
      'mode' => 'on_change',
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

  describe '#chek' do
    context 'when there is not another agent running' do
      context 'when review product is valid' do
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
            'title' => 'Some title',
            'comment' => 'good.',
            'appfigures_id' => '41013601294LtY5FiF31ODTSyH8hOem4Nw',
            'score' => '4.00',
            'stream' => 'google_play',
            'created_at' => '2018-02-09T11:45:38',
            'iso' => 'ZZ',
            'author' => 'Yang Li',
            'version' => '3.3.1003',
            'app' => 'reed.co.uk',
            'product_id' => 41013601294,
            'vendor_id' => 'com.reedcouk.jobs'
          }

          expect(payload).to eq(expected)
        end
      end

      context 'when review product is not valid' do
        before do
          @agent.options['products'] = '41013601294,41013601295'
          @agent.options['filter'] = 'count=5'
        end

        it 'does not emits events with another product id' do
          expect { @agent.check }.to change { Event.count }.by(4)

          products = @agent.events.map { |e| e.payload['product_id'] }
          expect(products.uniq).to eq([41013601294])
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
    it 'should generate a correct header' do
      expected = { "X-Client-Key" => "token123" }
      expect(@agent.send(:headers)).to eq(expected)
    end

    it 'build a correct params string' do
      expected = "products=41013601294&count=2"
      expect(@agent.send(:params)).to eq(expected)

      @agent.options['filter'] = ''
      expected = 'products=41013601294'
      expect(@agent.send(:params)).to eq(expected)

      @agent.options['products'] = ''
      expect(@agent.send(:params)).to be nil
    end

    it 'should generate a correct request_url' do
      expected = 'https://api.appfigures.com/v2/reviews?products=41013601294&count=2'
      expect(@agent.send(:request_url)).to eq(expected)

      @agent.options['filter'] = ''
      expected = 'https://api.appfigures.com/v2/reviews?products=41013601294'
      expect(@agent.send(:request_url)).to eq(expected)

      @agent.options['products'] = ''
      expect(@agent.send(:request_url)).to be nil
    end

    describe 'fetch_resource' do
      context 'when request_url is valid' do
        it 'returns a list of reviews' do
          expect(@agent.send(:fetch_resource)['reviews'].size).to eq(2)
        end
      end

      context 'when request_url is not present' do
        it 'returns an empty object' do
          @agent.options['products'] = ''
          expect(@agent.send(:fetch_resource)).to be nil
        end
      end

      context 'when get a failed response' do
        it 'returns an empty object' do
          @agent.options['filter'] = 'limit=2'
          expect(@agent.send(:fetch_resource)).to eq({})
          expect(@agent.logs.first.message).to eq('Error')
        end
      end
    end

    describe 'store_payload' do
      it 'returns true when mode is all or merge' do
        @agent.options['mode'] = 'all'
        expect(@agent.send(:store_payload!, [], 'key: 123')).to be true

        @agent.options['mode'] = 'merge'
        expect(@agent.send(:store_payload!, [], 'key: 123')).to be true
      end

      it 'raises an expception when mode is invalid' do
        @agent.options['mode'] = 'xyz'
        expect {
          @agent.send(:store_payload!, [], 'key: 123')
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
          expect(@agent.send(:store_payload!, @agent.events, 'comment' => 'somevalue')).to be false
        end

        it 'returns true if events does not exist' do
          expect(@agent.send(:store_payload!, @agent.events, 'comment' => 'othervalue')).to be true
        end
      end
    end

    describe 'previous_payloads' do
      before do
        Event.create payload: { 'comment' => 'some value'}, agent: @agent
        Event.create payload: { 'comment' => 'another value'}, agent: @agent
        Event.create payload: { 'comment' => 'other comment'}, agent: @agent
      end

      context 'when uniqueness_look_back is present' do
        before do
          @agent.options['uniqueness_look_back'] = 2
        end

        it 'returns a list of old events limited by uniqueness_look_back' do
          expect(@agent.events.count).to eq(3)
          expect(@agent.send(:previous_payloads, 1).count).to eq(2)
        end
      end

      context 'when uniqueness_look_back is not present' do
        it 'returns a list of old events limited by received events' do
          expect(@agent.events.count).to eq(3)
          expect(@agent.send(:previous_payloads, 1).count).to eq(3)
        end
      end

      it 'returns nil when mode is not on_change' do
        @agent.options['mode'] = 'all'
        expect(@agent.send(:previous_payloads, 1)).to be nil
      end
    end

    describe 'is_a_valid_product?' do
      before do
        @agent.options['products'] = "41013601294,41703131145,40326654086"
      end

      it 'returns true when is a valid product' do
        expect(@agent.send(:is_a_valid_product?, {'product_id' => '41013601294'})).to be true
      end

      it 'returns false when is not a valid product' do
        expect(@agent.send(:is_a_valid_product?, {'product_id' => '12345'})).to be false
      end
    end
  end
end
