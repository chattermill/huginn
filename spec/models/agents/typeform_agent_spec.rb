require 'rails_helper'

describe Agents::TypeformAgent do
  before do
    @opts = {
      "api_key": "token123",
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

    stub_request(:get, /api.typeform.com\/v1\/form/).to_return(
      body: File.read(Rails.root.join("spec/data_fixtures/typeform/form.json")),
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
      context 'with guess_mode as true' do
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
            'comment' => 'Siempre en atención al cliente se deben mejorar cosas. Es un muy buen servicio ',
            'created_at' => '2018-02-26 14:55:46',
            'id' => '6b3cd2e74489d2eb51b7df19a58769c4',
            'answers' => {
                "opinionscale_HBQFrgppgcZw" => "9",
                "textarea_cUFpnquv2orQ" => "Siempre en atención al cliente se deben mejorar cosas. Es un muy buen servicio ",
                "listimage_YJ8TmYnakZyy_choice" => "Hombre",
                "list_QI6De1wB6Fr8_choice" => "25 a 34"
            },
            'metadata' => {
              "date_land" => "2018-02-26 14:54:43",
              "date_submit" => "2018-02-26 14:55:46",
              "browser" => "fallback",
              "platform" => "tablet"
            },
            'hidden_variables' => {
              "token" => "d064a975-9c54-43de-8e70-071f0fe0bf12",
              "city_id" => "0",
              "country_id" => "38",
              "tc" => "12"
            }
          }

          expect(payload).to eq(expected)
        end
      end

      context 'with guess_mode as false' do
        before do
          @agent.options['guess_mode'] = false
          @agent.options['comment_question_ids'] = 'textarea_cUFpnquv2123'
          @agent.options['score_question_ids'] = 'opinionscale_HBQFrgppg123'
        end

        it 'emits events' do
          expect { @agent.check }.to change { Event.count }.by(2)
        end

        it 'does not emit duplicated events ' do
          @agent.check
          @agent.events.first.destroy

          expect { @agent.check }.to change { Event.count }.by(1)
          expect(@agent.events.count).to eq(2)
        end

        it 'emits correct payload' do
          @agent.check
          payload = @agent.events.first.payload
          expected = {
            'score' => '10',
            'comment' => 'Es un muy buen servicio',
            'created_at' => '2018-02-26 14:53:23',
            'id' => 'a290d8dbd146ad4ad4d7c13409e4578c',
            'answers' => {
              "opinionscale_HBQFrgppgcZw" => "7",
              "opinionscale_HBQFrgppg123" => "10",
              "textarea_cUFpnquv2orQ" => "Siempre en atención al cliente se deben mejorar cosas. Es un muy buen servicio ",
              "textarea_cUFpnquv2123" => "Es un muy buen servicio"
            },
            'metadata' => {
              "date_land" => "2018-02-26 14:53:05",
              "date_submit" => "2018-02-26 14:53:23",
              "browser" => "touch",
              "platform" => "mobile"
            },
            'hidden_variables' => {
              "token" => "526487cb-0c35-4f57-9ce3-ccfd8b6cb48d",
              "city_id" => "1434",
              "country_id" => "113",
              "tc" => "12"
            }
          }

          expect(payload).to eq(expected)
        end

        it 'emits score as nil if does not find any score question' do
          @agent.options['score_question_ids'] = 'none'
          @agent.check

          expect(@agent.events.last.payload['score']).to be nil
        end

        it 'emits comment as nil if does not find any comment question' do
          @agent.options['comment_question_ids'] = 'none'
          @agent.check

          expect(@agent.events.last.payload['comment']).to be nil
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
      expected = {
        "order_by[]" => "date_submit,desc",
        "limit" => 3,
        "offset" => 0
      }
      expect(@agent.send(:params)).to eq(expected)

      @agent.options['limit'] = ''
      @agent.options['offset'] = ''
      expected = {
        "order_by[]" => "date_submit,desc",
        "limit" => "",
        "offset" => ""
      }
      expect(@agent.send(:params)).to eq(expected)
    end
  end
end
