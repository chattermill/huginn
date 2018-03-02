require 'rails_helper'

describe Agents::TypeformWebhookAgent do
  before do
    VCR.insert_cassette 'typeform_webhook', record: :none, :match_requests_on => [:host], :allow_playback_repeats => true

    @opts = {
      'access_token' => 'token123',
      "form_id" => "jOyEkB",
      'guess_mode' => true,
      'mapping_object' => '{}',
      'bucketing_object' => '{}',
      "secret" => 'foobar',
      "expected_receive_period_in_days" => 1,
      "payload_path" => "."
    }

    @agent = Agents::TypeformWebhookAgent.new(:name => 'My agent', :options => @opts)
    @agent.user = users(:bob)
    @agent.save!
  end

  after do
    VCR.eject_cassette
  end

  let(:payload) { JSON.parse(File.read(Rails.root.join("spec/data_fixtures/typeform/webhook.json"))) }

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

  describe 'callback' do
    it 'perform a request to create or update the typeform webhook' do
      expect(WebMock).to have_requested(:put ,"https://api.typeform.com/forms/jOyEkB/webhooks/agent_#{@agent.id}")
      expect(@agent.logs.count).to eq(1)
      expect(@agent.logs.last.message).to match(/Typeform Response: 200/)
    end
  end

  describe 'receive_web_request' do
    it 'should create event if secret matches' do
      out = nil
      expect {
        out = @agent.receive_web_request(payload.merge('secret' => 'foobar'), "post", "application/json")
      }.to change { Event.count }.by(1)
      expect(out).to eq(['Event Created', 201])
      expect(Event.last.payload.key?('score')).to be true
    end

    it 'should not create event if secrets do not match' do
      out = nil
      expect {
        out = @agent.receive_web_request(payload.merge('secret' => 'booo'), "post", "text/html")
      }.to change { Event.count }.by(0)
      expect(out).to eq(['Not Authorized', 401])
    end

    it 'should respond with `201`' do
      out = @agent.receive_web_request(payload.merge('secret' => 'foobar'), "post", "application/json")
      expect(out).to eq(['Event Created', 201])
    end

    it "should accept POST" do
      out = nil
      expect {
        out = @agent.receive_web_request(payload.merge('secret' => 'foobar'), "post", "application/json")
      }.to change { Event.count }.by(1)
      expect(out).to eq(['Event Created', 201])
    end

    context 'when guess_mode is true' do
      it 'emits correct payload' do
        expected = {
          'score' => 2,
          'comment' => 'It\'s cold right now!',
          'created_at' => '2018-01-18T18:17:02Z',
          'id' => 'a3a12ec67a1365927098a606107fac15',
          'answers' => [
              {
                  "type" => "text",
                  "text" => "It's cold right now!",
                  "field" => {
                      "id" => "DlXFaesGBpoF",
                      "type" => "long_text"
                  }
              },
              {
                  "type" => "text",
                  "text" => "Laura",
                  "field" => {
                      "id" => "JwWggjAKtOkA",
                      "type" => "short_text"
                  }
              },
              {
                  "type" => "number",
                  "number" => 2,
                  "field" => {
                      "id" => "NRsxU591jIW9",
                      "type" => "opinion_scale"
                  }
              },
              {
                  "type" => "number",
                  "number" => 3,
                  "field" => {
                      "id" => "WOTdC00F8A3h",
                      "type" => "rating"
                  }
              }
          ],
          'formatted_answers' => {
            'long_text_DlXFaesGBpoF' => "It's cold right now!",
            'short_text_JwWggjAKtOkA' => 'Laura',
            'opinion_scale_NRsxU591jIW9' => 2,
            'rating_WOTdC00F8A3h' => 3
          },
          'metadata' => nil,
          'hidden_variables' => nil,
          'mapped_variables' => nil
        }
        out = nil
        expect {
          out = @agent.receive_web_request(payload.merge('secret' => 'foobar'), "post", "application/json")
        }.to change { Event.count }.by(1)
        expect(@agent.events.last.payload).to eq(expected)
      end

      it 'does not emit event if form_response field is not found' do
        expect {
          @agent.receive_web_request({'secret' => 'booo', 'some_key' => 'some value'}, "post", "text/html")
        }.to change { Event.count }.by(0)
      end

      it 'emits empty answer if there is no answers' do
        @agent.receive_web_request({'secret' => 'foobar', 'form_response' => { "answers" => [] }}, "post", "application/json")

        expect(@agent.events.last.payload['answers']).to eq([])
      end
    end

    context 'when guess_mode is true' do
      before do
        @agent.options['guess_mode'] = false
        @agent.options['score_question_ids'] = 'WOTdC00F8A3h'
        @agent.options['comment_question_ids'] = 'JwWggjAKtOkA'
      end
      it 'emits correct payload' do
        expected = {
          'score' => 3,
          'comment' => 'Laura',
          'created_at' => '2018-01-18T18:17:02Z',
          'id' => 'a3a12ec67a1365927098a606107fac15',
          'answers' => [
              {
                  "type" => "text",
                  "text" => "It's cold right now!",
                  "field" => {
                      "id" => "DlXFaesGBpoF",
                      "type" => "long_text"
                  }
              },
              {
                  "type" => "text",
                  "text" => "Laura",
                  "field" => {
                      "id" => "JwWggjAKtOkA",
                      "type" => "short_text"
                  }
              },
              {
                  "type" => "number",
                  "number" => 2,
                  "field" => {
                      "id" => "NRsxU591jIW9",
                      "type" => "opinion_scale"
                  }
              },
              {
                  "type" => "number",
                  "number" => 3,
                  "field" => {
                      "id" => "WOTdC00F8A3h",
                      "type" => "rating"
                  }
              }
          ],
          'formatted_answers' => {
            'long_text_DlXFaesGBpoF' => "It's cold right now!",
            'short_text_JwWggjAKtOkA' => 'Laura',
            'opinion_scale_NRsxU591jIW9' => 2,
            'rating_WOTdC00F8A3h' => 3
          },
          'metadata' => nil,
          'hidden_variables' => nil,
          'mapped_variables' => nil
        }
        out = nil
        expect {
          out = @agent.receive_web_request(payload.merge('secret' => 'foobar'), "post", "application/json")
        }.to change { Event.count }.by(1)
        expect(@agent.events.last.payload).to eq(expected)
      end

      it 'does not emit event if form_response field is not found' do
        expect {
          @agent.receive_web_request({'secret' => 'booo', 'some_key' => 'some value'}, "post", "text/html")
        }.to change { Event.count }.by(0)
      end

      it 'emits score as nil if does not find any score question' do
        @agent.options['score_question_ids'] = 'abcde'
        @agent.receive_web_request(payload.merge('secret' => 'foobar'), "post", "application/json")

        expect(@agent.events.last.payload['score']).to be nil
      end

      it 'emits comment as nil if does not find any comment question' do
        @agent.options['comment_question_ids'] = 'abcde'
        @agent.receive_web_request(payload.merge('secret' => 'foobar'), "post", "application/json")

        expect(@agent.events.last.payload['comment']).to be nil
      end

      it 'emits empty answer if there is no answers' do
        @agent.receive_web_request({'secret' => 'foobar', 'form_response' => { "answers" => [] }}, "post", "application/json")

        expect(@agent.events.last.payload['answers']).to eq([])
      end
    end

    context 'with mapping_object' do
      let(:payload) { JSON.parse(File.read(Rails.root.join("spec/data_fixtures/typeform/webhook_with_hidden_field.json"))) }

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

        expected = {
          "city_id" => "New York",
          "country_id" => "US"
        }

        @agent.receive_web_request(payload.merge('secret' => 'foobar'), "post", "application/json")
        expect(@agent.events.last.payload['mapped_variables']).to eq(expected)
      end
    end

    context 'with bucketing_object' do
      let(:payload) { JSON.parse(File.read(Rails.root.join("spec/data_fixtures/typeform/webhook_with_hidden_field.json"))) }

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
        @agent.receive_web_request(payload.merge('secret' => 'foobar'), "post", "application/json")

        expect(@agent.events.last.payload['mapped_variables']).to eq({"tc" => "101 and more"})
      end
    end
  end
end
