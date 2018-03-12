require 'rails_helper'

describe Agents::TypeformResponseAgent do
  before do

    @opts = {
      "access_token": "token123",
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

    stub_request(:get, /api.typeform.com\/forms/).to_return(
      body: File.read(Rails.root.join("spec/data_fixtures/typeform/responses.json")),
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
    context 'with guess_mode as true' do
      it 'emits events' do
        expect { @agent.check }.to change { Event.count }.by(4)
      end

      it 'does not emit duplicated events ' do
        @agent.check
        @agent.events.last.destroy

        expect(@agent.events.count).to eq(3)
        expect { @agent.check }.to change { Event.count }.by(1)
        expect(@agent.events.count).to eq(4)
      end

      it 'emits correct payload' do
        @agent.check
        payload = @agent.events.first.payload
        expected = {
          'score' => 7,
          'comment' => 'recomendaría 2 sugerencias, gracias y saludos',
          'created_at' => '2018-02-26T15:34:04Z',
          'id' => '6c0fba887ea25563f0592c8d09fad62a',
          'answers' => [
              {
                  "field" => {
                      "id" => "HBQFrgppgcZw",
                      "type" => "opinion_scale"
                  },
                  "type" => "number",
                  "number" => 7
              },
              {
                  "field" => {
                      "id" => "QI6De1wB6Fr8",
                      "type" => "multiple_choice"
                  },
                  "type" => "choice",
                  "choice" => {
                      "label" => "25 a 34"
                  }
              },
              {
                  "field" => {
                      "id" => "YJ8TmYnakZyy",
                      "type" => "picture_choice"
                  },
                  "type" => "choice",
                  "choice" => {
                      "label" => "Hombre"
                  }
              },
              {
                  "field" => {
                      "id" => "cUFpnquv2orQ",
                      "type" => "long_text"
                  },
                  "type" => "text",
                  "text" => "recomendaría 2 sugerencias, gracias y saludos"
              }
          ],
          'formatted_answers' => {
            "opinion_scale_HBQFrgppgcZw" => 7,
            "multiple_choice_QI6De1wB6Fr8" => {
                "label" => "25 a 34"
            },
            "picture_choice_YJ8TmYnakZyy" => {
                "label" => "Hombre"
            },
            "long_text_cUFpnquv2orQ" => "recomendaría 2 sugerencias, gracias y saludos",

          },
          'metadata' => {
              "user_agent" => "Mozilla/5.0 (Linux; Android 7.0; SM-A720F Build/NRD90M) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.137 Mobile Safari/537.36",
              "platform" => "mobile",
              "referer" => "https://uberperu.typeform.com/to/uOSkwS?token=afbaece5-de51-493e-be92-57f1c9d462e0&city_id=0&country_id=8&tc=26",
              "network_id" => "a7c55107aa",
              "browser" => "touch"
          },
          'hidden_variables' => {
              "city_id" => "0",
              "country_id" => "8",
              "tc" => "26",
              "token" => "afbaece5-de51-493e-be92-57f1c9d462e0"
          },
          'mapped_variables' => {}
        }

        expect(payload).to eq(expected)
      end

      it 'emits score as nil if does not find any score question' do
        @agent.check
        event = @agent.events.second

        expect(event.payload['score']).to be nil
      end

      it 'emits comment as nil if does not find any comment question' do
        @agent.check
        event = @agent.events.second

        expect(event.payload['comment']).to be nil
      end

      it 'emits empty answer if there is no answers' do
        @agent.check
        event = @agent.events.third

        expect(event.payload['answers']).to eq([])
      end
    end

    context 'with guess_mode as false' do
      before do
        @agent.options['guess_mode'] = false
        @agent.options['comment_question_ids'] = 'cUFpnquv2orQ'
        @agent.options['score_question_ids'] = 'HBQFrgp123Zw'
      end

      it 'emits events' do
        expect { @agent.check }.to change { Event.count }.by(4)
      end

      it 'does not emit duplicated events ' do
        @agent.check
        @agent.events.last.destroy

        expect(@agent.events.count).to eq(3)
        expect { @agent.check }.to change { Event.count }.by(1)
        expect(@agent.events.count).to eq(4)
      end

      it 'emits correct payload' do
        @agent.check

        expected = {
          'score' => 2,
          'comment' => 'gracias y saludos',
          'created_at' => '2018-02-23T18:38:47Z',
          'id' => 'a6a996a607d808f826d7edb2d4b404cb',
          'answers' => [
            {
              "field" => {
                "id" => "27098511",
                "type" => "long_text"
              },
              "type" => "text",
              "text" => "Better  instructions....very specific as to what I will see and what I must do with  examples"
            },
            {
                "field" => {
                    "id" => "HBQFrgp123Zw",
                    "type" => "opinion_scale"
                },
                "type" => "number",
                "number" => 2
            },
            {
                "field" => {
                    "id" => "HBQFrgppgcZw",
                    "type" => "opinion_scale"
                },
                "type" => "number",
                "number" => 7
            },
            {
                "field" => {
                    "id" => "cUFpnquv2orQ",
                    "type" => "long_text"
                },
                "type" => "text",
                "text" => "gracias y saludos"
            }
          ],
          'formatted_answers' => {
            "long_text_27098511" => "Better  instructions....very specific as to what I will see and what I must do with  examples",
            "opinion_scale_HBQFrgp123Zw" => 2,
            "opinion_scale_HBQFrgppgcZw" => 7,
            "long_text_cUFpnquv2orQ" => "gracias y saludos"
          },
          'metadata' => {
            "user_agent" => "Mozilla/5.0  (Macintosh; Intel Mac OS X 10_12_6) AppleWebKit/537.36 (KHTML, like Gecko)  Chrome/64.0.3282.167 Safari/537.36",
            "platform" => "other",
            "referer" => "https://transferwise.typeform.com/to/D7aM1F?userprofile=4.835.494&score=1&language=es",
            "network_id" => "90a2e46c14",
            "browser" => "default"
          },
          'hidden_variables' => {
            "language" => "es",
            "score" => "1",
            "userprofile" => "4.835.494",
            "tc" => ""
          },
          'mapped_variables' => {}
        }

        expect(@agent.events.last.payload).to eq(expected)
      end

      it 'emits score as nil if score question does not exist' do
        @agent.options['score_question_ids'] = '123'
        @agent.check

        expect(@agent.events.last.payload['score']).to be nil
      end

      it 'emits comment as nil if score question does not exist' do
        @agent.options['comment_question_ids'] = '123'
        @agent.check

        expect(@agent.events.last.payload['comment']).to be nil
      end

      it 'emits empty answer if there is no answers' do
        @agent.check
        event = @agent.events.third

        expect(event.payload['answers']).to eq([])
      end
    end

    context 'with mapping_object' do
      it 'build the mapped_variables correctly' do
        @agent.options['mapping_object'] = {
          "city_id": {
            "0": "London",
            "1": "New York"
          },
          "country_id": {
            "1": "UK",
            "8": "US"
          }
        }
        @agent.check
        expected = {
          "city_id" => "London",
          "country_id" => "US"
        }

        expect(@agent.events.first.payload['mapped_variables']).to eq(expected)
      end
    end

    context 'with bucketing_object' do
      it 'build the mapped_variables correctly' do
        @agent.options['bucketing_object'] = {
          "tc": {
            "1": "First Trip",
            "2-10": "2 - 10",
            "11-20": "11 - 20",
            "21-50": "21 - 50",
            "51-100": "51 - 100",
            "100+": "101 and more"
          }
        }
        @agent.check

        expect(@agent.events.first.payload['mapped_variables']).to eq({"tc" => "21 - 50"})
        expect(@agent.events.second.payload['mapped_variables']).to eq({"tc" => "101 and more"})
        expect(@agent.events.last.payload['mapped_variables']).to eq({"tc" => ""})
      end
    end
  end

  describe 'helpers' do

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

    describe 'params' do
      it 'should generate params correctly' do
        @agent.options['limit'] = 3
        @agent.options['since'] = "02-20-2018"
        @agent.options['until'] = "02-21-2018"

        expected = {
          'page_size' => 3,
          'since' => '2018-02-20T12:00:00',
          'until' => '2018-02-21T12:00:00',
        }

        expect(@agent.send(:params)).to eq(expected)

        @agent.options['since'] = "xxxx"
        expect(@agent.send(:params)).to eq(expected.except('since'))

      end
    end
  end
end
