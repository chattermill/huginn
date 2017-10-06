require 'rails_helper'
require 'ostruct'

describe Agents::ChattermillResponseAgent do
  let(:segments) do
    { 'segment_id' => { 'type' => 'text', 'name' => 'Segment Id', 'value' => '{{data.segment}}' } }
  end

  let(:user_meta) do
    { 'meta_id' => { 'type' => 'text', 'name' => 'Meta Id' } }
  end

  before do
    stub.proxy(ENV).[](anything)
    stub(ENV).[]('CHATTERMILL_AUTH_TOKEN') { 'token-123' }

    @valid_options = {
      'organization_subdomain' => 'foo',
      'expected_receive_period_in_days' => 1,
      'comment' => '{{ data.comment }}',
      'segments' => segments.to_json,
      'user_meta' => user_meta.to_json,
      'extra_fields' => '{}',
      'send_batch_events' => 'false',
      'max_events_on_buffer' => 3
    }
    @valid_params = {
      name: "somename",
      options: @valid_options
    }

    @checker = Agents::ChattermillResponseAgent.new(@valid_params)
    @checker.user = users(:jane)
    @checker.save!

    @event = Event.new
    @event.agent = agents(:jane_weather_agent)
    @event.payload = {
      'somekey' => 'somevalue',
      'data' => {
        'comment' => 'Test Comment'
      }
    }
    @requests = 0
    @sent_requests = Hash.new { |hash, method| hash[method] = [] }

    stub_request(:any, /:/).to_return { |request|
      method = request.method
      @requests += 1
      @sent_requests[method] << req = OpenStruct.new(uri: request.uri, headers: request.headers)
      req.data = ActiveSupport::JSON.decode(request.body)
      if request.headers['Authorization'] =~ /invalid/
        { status: 401, body: '{"error": "Unauthorized"}', headers: { 'Content-type' => 'application/json' } }
      else
        { status: 201, body: '{}', headers: { 'Content-type' => 'application/json' } }
      end
    }
  end

  it_behaves_like WebRequestConcern

  it 'renders the description markdown without errors' do
    expect { @checker.description }.not_to raise_error
  end

  describe "making requests" do
    context 'when send_batch_events is false' do
      it "makes POST requests" do
        expect(@checker).to be_valid
        @checker.check
        expect(@requests).to eq(1)
        expect(@sent_requests[:post].length).to eq(1)
      end

      it "uses the correct URI" do
        @checker.check
        uri = @sent_requests[:post].first.uri.to_s
        expect(uri).to eq("http://localhost:3000/webhooks/responses/")
      end

      it "generates the authorization header" do
        @checker.check
        auth_header = @sent_requests[:post].first.headers['Authorization']
        expect(auth_header).to eq("Bearer token-123")
      end

      it "generates the organization header" do
        @checker.check
        org_header = @sent_requests[:post].first.headers['Organization']
        expect(org_header).to eq('foo')
      end
    end

    context 'when send_batch_events is true' do
      before do
        @valid_options.merge!('send_batch_events' => 'true')

        @checker = Agents::ChattermillResponseAgent.new({ name: "othername",
                                                          options: @valid_options })
        @checker.user = users(:jane)
        @checker.save!
      end

      context 'when memory is empty' do
        it "doesn't make POST requests" do
          expect(@checker).to be_valid
          @checker.check
          expect(@requests).to eq(0)
          expect(@sent_requests[:post].length).to eq(0)
          expect(@checker.memory.key?('events')).to be false
        end
      end

      context 'when memory is not empty' do
        before do
          other_event = Event.new
          other_event.agent = agents(:jane_weather_agent)
          other_event.payload = {
            'somekey' => 'somevalue',
            'data' => {
              'comment' => 'Test Comment 2'
            }
          }
          @checker.memory['events'] = [@event.id, other_event.id]
        end

        it "makes POST requests" do
          expect(@checker).to be_valid
          expect(@checker.memory['events'].length).to eq(2)
          @checker.check
          expect(@requests).to eq(1)
          expect(@sent_requests[:post].length).to eq(1)
        end

        it "uses the correct URI" do
          @checker.check
          uri = @sent_requests[:post].first.uri.to_s
          expect(uri).to eq("http://localhost:3000/webhooks/responses/bulk")
        end

        it "generates the authorization header" do
          @checker.check
          auth_header = @sent_requests[:post].first.headers['Authorization']
          expect(auth_header).to eq("Bearer token-123")
        end

        it "generates the organization header" do
          @checker.check
          org_header = @sent_requests[:post].first.headers['Organization']
          expect(org_header).to eq('foo')
        end

        it 'clean memory' do
          expect(@checker.memory['events'].length).to eq(2)
          @checker.check
          expect(@checker.memory['events']).to be_empty
        end
      end
    end
  end

  describe "#receive" do
    context 'when send_batch_events is false' do
      it "can handle events with id" do
        @checker.options['id'] = '123'
        @checker.check

        expect(@sent_requests[:patch].length).to eq(1)
        uri = @sent_requests[:patch].first.uri.to_s
        expect(uri).to eq("http://localhost:3000/webhooks/responses/123")
      end

      it "can handle multiple events" do
        event1 = Event.new
        event1.agent = agents(:bob_weather_agent)
        event1.payload = {
          'xyz' => 'value1',
          'data' => {
            'segment' => 'My Segment'
          }
        }

        expect {
          @checker.receive([@event, event1])
        }.to change { @sent_requests[:post].length }.by(2)

        expected = {
          'comment' => 'Test Comment',
          'segments' => { 'segment_id' => { 'type' => 'text', 'name' => 'Segment Id', 'value' => '' } },
          'user_meta' => user_meta
        }
        expect(@sent_requests[:post][0].data).to eq(expected)

        expected = {
          'segments' => { 'segment_id' => { 'type' => 'text', 'name' => 'Segment Id', 'value' => 'My Segment' } },
          'user_meta' => user_meta
        }
        expect(@sent_requests[:post][1].data).to eq(expected)
      end

      describe "emitting events" do
        context "when emit_events is not set to true" do
          it "does not emit events" do
            expect {
              @checker.receive([@event])
            }.not_to change { @checker.events.count }
          end
        end

        context "when emit_events is set to true" do
          before do
            @checker.options['emit_events'] = 'true'
          end

          it "emits the response status" do
            expect {
              @checker.receive([@event])
            }.to change { @checker.events.count }.by(1)
            expect(@checker.events.last.payload['status']).to eq 201
          end

          it "emits the body" do
            @checker.receive([@event])
            expect(@checker.events.last.payload['body']).to eq '{}'
          end

          it "emits the response headers capitalized by default" do
            @checker.receive([@event])
            expect(@checker.events.last.payload['headers']).to eq({ 'Content-Type' => 'application/json' })
          end

          it "emits the source event" do
            @checker.receive([@event])
            expect(@checker.events.last.payload['source_event']).to eq @event.id
          end
        end

        describe "whith valid kind and score" do
          before do
            options = @valid_options.merge(
              'score' => '{{ data.score }}',
              'kind' => 'csat',
              'emit_events' => true
            )

            @checker = Agents::ChattermillResponseAgent.create(
              name: 'valid',
              options: options,
              user: users(:jane)
            )
          end

          it "emits event" do
            @event.payload['data']['score'] = '10'

            expect {
              @checker.receive([@event])
            }.to change { @checker.events.count }.by(1)
          end
        end

        describe "when payload validation fails" do
          before do
            options = @valid_options.merge(
              'score' => '{{ data.score }}',
              'kind' => 'nps',
              'emit_events' => true
            )

            @checker = Agents::ChattermillResponseAgent.create(
              name: 'invalid',
              options: options,
              user: users(:jane)
            )
          end

          it "doesn't emit events" do
            @event.payload['data']['score'] = ''

            expect {
              @checker.receive([@event])
            }.not_to change { @checker.events.count }
          end

          it "logs a message with validation error" do
            @event.payload['data']['score'] = ''
            @event.save

            expect {
              @checker.receive([@event])
            }.to change { @checker.logs.count }.by(1)

            error = JSON.parse(@checker.logs.last.message)
            expected = { "score" => ["can't be blank", "is not a number"], "source_event" => @event.id }
            expect(error).to eq(expected)
          end
        end
      end
    end

    context 'when send_batch_events is true' do
      before do
        @valid_options.merge!('send_batch_events' => 'true')

        @checker = Agents::ChattermillResponseAgent.new({ name: "othername",
                                                          options: @valid_options })
        @checker.user = users(:jane)
        @checker.save!
      end

      it "save events in buffer" do
        expect {
          @checker.receive([@event])
        }.to change { @sent_requests[:post].length }.by(0)

        expect(@checker.memory['events'].length).to eq(1)
        expect(@checker.memory['events']).to eq([@event.id])
      end

      it "can handle multiple events" do
        event1 = Event.new
        event1.agent = agents(:bob_weather_agent)
        event1.payload = {
          'xyz' => 'value1',
          'data' => {
            'segment' => 'My Segment'
          }
        }

        expect {
          @checker.receive([@event, event1])
        }.to change { @sent_requests[:post].length }.by(0)

        expect(@checker.memory['events'].length).to eq(2)
      end

      it "emit events when max events in buffer is reached" do
        event1 = Event.new
        event1.agent = agents(:bob_weather_agent)
        event1.payload = {
          'xyz' => 'value1',
          'data' => {
            'segment' => 'My Segment'
          }
        }
        event2 = Event.new
        event2.agent = agents(:bob_weather_agent)
        event2.payload = {
          'abc' => 'value1',
          'data' => {
            'comment' => 'Hello'
          }
        }

        @checker.receive([@event, event1])

        expect(@checker.memory['events'].length).to eq(2)
        expect {
          @checker.receive([event2])
        }.to change { @sent_requests[:post].length }.by(1)

        expect(@checker.memory['events'].length).to eq(0)
      end
    end
  end

  describe "#check" do
    context 'when send_batch_events is false' do
      it "sends data as a POST request" do
        expect {
          @checker.check
        }.to change { @sent_requests[:post].length }.by(1)

        expected = {
          'segments' => { 'segment_id' => { 'type' => 'text', 'name' => 'Segment Id', 'value' => '' } },
          'user_meta' => user_meta
        }
        expect(@sent_requests[:post][0].data).to eq(expected)
      end

      describe "emitting events" do
        context "when emit_events is not set to true" do
          it "does not emit events" do
            expect {
              @checker.check
            }.not_to change { @checker.events.count }
          end
        end

        context "when emit_events is set to true" do
          before do
            @checker.options['emit_events'] = 'true'
          end

          it "emits the response status" do
            expect {
              @checker.check
            }.to change { @checker.events.count }.by(1)
            expect(@checker.events.last.payload['status']).to eq 201
          end

          it "emits the body" do
            @checker.check
            expect(@checker.events.last.payload['body']).to eq '{}'
          end

          it "emits the response headers capitalized by default" do
            @checker.check
            expect(@checker.events.last.payload['headers']).to eq({ 'Content-Type' => 'application/json' })
          end

          it "emits the source event" do
            @checker.check
            expect(@checker.events.last.payload['source_event']).to be_nil
          end
        end
      end

      describe "slack notification" do
        before do
          stub(ENV).[]('CHATTERMILL_AUTH_TOKEN') { 'invalid' }
          stub(ENV).[]('SLACK_WEBHOOK_URL') { 'http://slack.webhook/abc' }
          stub(ENV).[]('SLACK_CHANNEL') { '#mychannel' }
        end

        it "sends a slack notification" do
          slack = mock
          mock(slack).ping('', hash_including({ icon_emoji: ':fire:', channel: '#mychannel' })) { true }
          mock(Slack::Notifier).new('http://slack.webhook/abc', { username: 'Huginn' }) { slack }
          @checker.check
        end
      end
    end

    context 'when send_batch_events is true' do
      before do
        @valid_options.merge!('send_batch_events' => 'true', 'max_events_on_buffer' => 2)

        @checker = Agents::ChattermillResponseAgent.new({ name: "othername",
                                                          options: @valid_options })
        @checker.user = users(:jane)
        @checker.save!
      end

      it 'does not emit events if max events in buffer is not reached' do
        @checker.receive([@event])

        expect {
          @checker.check
        }.not_to change { @checker.events.count }
      end

      it "sends data as a POST request" do
        event1 = Event.new
        event1.agent = agents(:bob_weather_agent)
        event1.payload = {
          'xyz' => 'value1',
          'data' => {
            'segment' => 'My Segment'
          }
        }
        event1.save

        @checker.memory['events'] = [@event.id, event1.id]

        expect {
          @checker.check
        }.to change { @sent_requests[:post].length }.by(1)

        expect(@checker.memory['events'].length).to eq(0)
      end


    end
  end

  describe "#working?" do
    it "checks if events have been received within expected receive period" do
      expect(@checker).not_to be_working
      described_class.async_receive @checker.id, [@event.id]
      expect(@checker.reload).to be_working
      two_days_from_now = 2.days.from_now
      stub(Time).now { two_days_from_now }
      expect(@checker.reload).not_to be_working
    end
  end

  describe "validation" do
    before do
      expect(@checker).to be_valid
    end

    it "should validate presence of post_url" do
      @checker.options['organization_subdomain'] = ""
      expect(@checker).not_to be_valid
    end

    it "should validate presence of expected_receive_period_in_days" do
      @checker.options['expected_receive_period_in_days'] = ""
      expect(@checker).not_to be_valid
    end

    it "should validate segments as a hash" do
      @checker.options['segments'] = {}
      @checker.save
      expect(@checker).to be_valid
    end

    it "should validate segments as a JSON string" do
      @checker.options['segments'] = segments.to_json
      @checker.save
      expect(@checker).to be_valid

      @checker.options['segments'] = "invalid json"
      @checker.save
      expect(@checker).to_not be_valid
    end

    it "should validate user_meta as a hash" do
      @checker.options['user_meta'] = {}
      @checker.save
      expect(@checker).to be_valid
    end

    it "should validate user_meta as a JSON string" do
      @checker.options['user_meta'] = segments.to_json
      @checker.save
      expect(@checker).to be_valid

      @checker.options['user_meta'] = "invalid json"
      @checker.save
      expect(@checker).to_not be_valid
    end

    it "should validate extra_fields as a hash" do
      @checker.options['extra_fields'] = {}
      @checker.save
      expect(@checker).to be_valid
    end

    it "should validate extra_fields as a JSON string" do
      @checker.options['extra_fields'] = '{}'
      @checker.save
      expect(@checker).to be_valid

      @checker.options['extra_fields'] = "invalid json"
      @checker.save
      expect(@checker).to_not be_valid
    end

    it "requires emit_events to be true or false" do
      @checker.options['emit_events'] = 'what?'
      expect(@checker).not_to be_valid

      @checker.options.delete('emit_events')
      expect(@checker).to be_valid

      @checker.options['emit_events'] = 'true'
      expect(@checker).to be_valid

      @checker.options['emit_events'] = 'false'
      expect(@checker).to be_valid

      @checker.options['emit_events'] = true
      expect(@checker).to be_valid
    end

    it "requires send_batch_events to be true or false" do
      @checker.options['max_events_on_buffer'] = "10"
      @checker.options['send_batch_events'] = 'what?'
      expect(@checker).not_to be_valid

      @checker.options.delete('send_batch_events')
      expect(@checker).to be_valid

      @checker.options['send_batch_events'] = 'true'
      expect(@checker).to be_valid

      @checker.options['send_batch_events'] = 'false'
      expect(@checker).to be_valid

      @checker.options['send_batch_events'] = true
      expect(@checker).to be_valid
    end

    it "should validate max_events_on_buffer" do
      @checker.options.delete('max_events_on_buffer')
      expect(@checker).to be_valid
      @checker.options['send_batch_events'] = true
      expect(@checker).not_to be_valid
      @checker.options['max_events_on_buffer'] = ""
      expect(@checker).not_to be_valid
      @checker.options['max_events_on_buffer'] = "0"
      expect(@checker).not_to be_valid
      @checker.options['max_events_on_buffer'] = "10"
      expect(@checker).to be_valid
    end
  end
end
