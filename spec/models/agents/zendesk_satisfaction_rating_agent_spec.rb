require 'rails_helper'

describe Agents::ZendeskSatisfactionRatingsAgent do
  before do

    @opts = {
      "subdomain": "foo",
      "account_email": "name@example.com",
      "api_token": "etNzSER4H3sYsWk4dyO6cD4O04KbBwBxHNvchlTw",
      "filter": "sort_order=desc&score=received_with_comment",
      'expected_update_period_in_days' => '2',
      'mode' => 'on_change',
      'retrieve_assignee' => 'false',
      'retrieve_ticket' => 'false',
      'retrieve_group' => 'false'
    }
    @agent = Agents::ZendeskSatisfactionRatingsAgent.new(:name => 'My agent', :options => @opts)
    @agent.user = users(:bob)
    @agent.save!

    stub_request(:get, /zendesk.com\/api\/v2\/satisfaction_ratings/).to_return(
      body: File.read(Rails.root.join("spec/data_fixtures/zendesk/satisfaction_ratings.json")),
      headers: {"Content-Type"=> "application/json"},
      status: 200)
    stub_request(:get, /zendesk.com\/api\/v2\/tickets/).to_return(
      body: File.read(Rails.root.join("spec/data_fixtures/zendesk/tickets.json")),
      headers: {"Content-Type"=> "application/json"},
      status: 200)
    stub_request(:get, /zendesk.com\/api\/v2\/groups/).to_return(
      body: File.read(Rails.root.join("spec/data_fixtures/zendesk/groups.json")),
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

    it 'should validate presence of subdomain' do
      @agent.options['subdomain'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of api_token' do
      @agent.options['api_token'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of account_email' do
      @agent.options['account_email'] = ''
      expect(@agent).not_to be_valid

      @agent.options['use_oauth'] = true
      expect(@agent).to be_valid
    end

    it 'should validate retrieve_assignee value' do
      @agent.options['retrieve_assignee'] = nil
      expect(@agent).not_to be_valid

      @agent.options['retrieve_assignee'] = 'xyz'
      expect(@agent).not_to be_valid
    end

    it 'should validate retrieve_ticket value' do
      @agent.options['retrieve_ticket'] = nil
      expect(@agent).not_to be_valid

      @agent.options['retrieve_ticket'] = 'xyz'
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
    end

    it 'emits correct payload' do
      @agent.check
      expected = {
        "id" => 360080079073,
        "url" => "https://example.com/api/v2/satisfaction_ratings/360080079073.json",
        "assignee_id" => 114996813853,
        "group_id" => 32148188,
        "requester_id" => 360525488253,
        "ticket_id" => 1027403,
        "score" => "good",
        "updated_at" => "2018-02-27T19:49:55Z",
        "created_at" => "2018-02-27T19:49:55Z",
        "comment" => "Incredibly satisfied all member's that emailed me helped greatly and in the end helped fix my problem gave me every bit of info i needed and more very thankful 110% happy"
      }

      expect(@agent.events.last.payload).to eq(expected)
    end

    context 'when retrieve_assignee is true' do
      it 'emits correct payload' do
        @agent.options['retrieve_assignee'] = 'true'
        @agent.save!
        @agent.check
        expected = {
          "id" => 360080079073,
          "url" => "https://example.com/api/v2/satisfaction_ratings/360080079073.json",
          "assignee_id" => 114996813853,
          "group_id" => 32148188,
          "requester_id" => 360525488253,
          "ticket_id" => 1027403,
          "score" => "good",
          "updated_at" => "2018-02-27T19:49:55Z",
          "created_at" => "2018-02-27T19:49:55Z",
          "comment" => "Incredibly satisfied all member's that emailed me helped greatly and in the end helped fix my problem gave me every bit of info i needed and more very thankful 110% happy",
          "user" => {
            "id" => 114996813853,
            "url" => "https://example.com",
            "name" => "Rachel",
            "email" => "r.meyer@example.com",
            "created_at" => "2017-09-18T17:25:35Z",
            "updated_at" => "2018-02-27T14:57:54Z",
            "time_zone" => "Pacific Time (US & Canada)",
            "phone" => nil,
            "shared_phone_number" => nil,
            "photo" => {
                "url" => "https://example.com",
                "id" => 114111018053,
                "file_name" => "7a6483ad1f0410e80d9b2cf75e6eb92f--dog-smiling-need-to-lose-weight.jpg",
                "content_url" => "https://example.com",
                "mapped_content_url" => "https://example.com",
                "content_type" => "image/jpeg",
                "size" => 1454,
                "width" => 80,
                "height" => 80,
                "inline" => false,
                "thumbnails" => []
            },
            "locale_id" => 1,
            "locale" => "en-US",
            "organization_id" => nil,
            "role" => "agent",
            "verified" => true,
            "external_id" => nil,
            "tags" => [],
            "alias" => "",
            "active" => true,
            "shared" => false,
            "shared_agent" => false,
            "last_login_at" => "2018-02-27T14:57:54Z",
            "two_factor_auth_enabled" => nil,
            "signature" => "",
            "details" => "",
            "notes" => "",
            "role_type" => 0,
            "custom_role_id" => 750377,
            "moderator" => false,
            "ticket_restriction" => nil,
            "only_private_comments" => false,
            "restricted_agent" => false,
            "suspended" => false,
            "chat_only" => false,
            "default_group_id" => 20503477,
            "user_fields" => {
                "device_information" => nil,
                "full_name" => nil,
                "games_played" => nil,
                "notes" => nil,
                "support_id" => nil,
                "system::embeddable_last_seen" => "2018-01-24T00:00:00+00:00"
            }
          }
        }

        expect(@agent.events.last.payload).to eq(expected)
      end
    end

    context 'when retrieve_ticket is true' do
      it 'emits correct payload' do
        @agent.options['retrieve_ticket'] = 'true'
        @agent.save
        @agent.check

        expected = {
          "id" => 360080079073,
          "url" => "https://example.com/api/v2/satisfaction_ratings/360080079073.json",
          "assignee_id" => 114996813853,
          "group_id" => 32148188,
          "requester_id" => 360525488253,
          "ticket_id" => 1027403,
          "score" => "good",
          "updated_at" => "2018-02-27T19:49:55Z",
          "created_at" => "2018-02-27T19:49:55Z",
          "comment" => "Incredibly satisfied all member's that emailed me helped greatly and in the end helped fix my problem gave me every bit of info i needed and more very thankful 110% happy",
          "ticket" => {
            "url" => "https://example.com/api/v2/tickets/1027403.json",
            "id" => 1027403,
            "external_id" => nil,
            "via" => {
                "channel" => "web",
                "source" => {
                    "from" => {},
                    "to" => {},
                    "rel" => nil
                }
            },
            "created_at" => "2018-02-14T03:19:04Z",
            "updated_at" => "2018-02-27T19:49:55Z",
            "type" => "incident",
            "subject" => "Episode ",
            "raw_subject" => "Episode ",
            "description" => "App keeps glitching and taling me out of it ",
            "priority" => nil,
            "status" => "solved",
            "recipient" => nil,
            "requester_id" => 360525488253,
            "submitter_id" => 360525488253,
            "assignee_id" => 114996813853,
            "organization_id" => nil,
            "group_id" => 32148188,
            "collaborator_ids" => [],
            "follower_ids" => [],
            "forum_topic_id" => nil,
            "problem_id" => nil,
            "has_incidents" => false,
            "is_public" => true,
            "due_at" => nil,
            "tags" => [
                "account_transfer",
                "android"
            ],
            "custom_fields" => [
                {
                    "id" => 24028428,
                    "value" => false
                }
            ],
            "satisfaction_rating" => {
                "score" => "good",
                "id" => 360080079073,
                "comment" => "Incredibly satisfied all member's that emailed me helped greatly and in the end helped fix my problem gave me every bit of info i needed and more very thankful 110% happy",
                "reason" => "No reason provided",
                "reason_id" => 787
            },
            "sharing_agreement_ids" => [],
            "fields" => [
                {
                    "id" => 24028428,
                    "value" => false
                }
            ],
            "followup_ids" => [],
            "ticket_form_id" => 112758,
            "brand_id" => 114094495673,
            "satisfaction_probability" => nil,
            "allow_channelback" => false
          }
        }
        expect(@agent.events.last.payload).to eq(expected)
      end
    end

    context 'when retrieve_group is true' do
      it 'emits correct payload' do
        @agent.options['retrieve_group'] = 'true'
        @agent.save!
        @agent.check

        expected = {
          "id" => 360080079073,
          "url" => "https://example.com/api/v2/satisfaction_ratings/360080079073.json",
          "assignee_id" => 114996813853,
          "group_id" => 32148188,
          "requester_id" => 360525488253,
          "ticket_id" => 1027403,
          "score" => "good",
          "updated_at" => "2018-02-27T19:49:55Z",
          "created_at" => "2018-02-27T19:49:55Z",
          "comment" => "Incredibly satisfied all member's that emailed me helped greatly and in the end helped fix my problem gave me every bit of info i needed and more very thankful 110% happy",
          "group" => {
            "url" => "https://example.com/api/v2/groups/32148188.json",
            "id" => 32148188,
            "name" => "Episode",
            "deleted" => false,
            "created_at" => "2016-09-29T22:08:06Z",
            "updated_at" => "2016-09-29T22:08:06Z"
          }
        }
        expect(@agent.events.last.payload).to eq(expected)
      end
    end
  end

  describe 'helpers' do
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
            'comment' => 'somevalue',
            'id' => 12345
          }
          @event.save!
        end

        it 'returns false if events exist' do
          expect(@agent.send(:store_payload!, @agent.events, 'comment' => 'somevalue', 'id' => 12345)).to be false
        end

        it 'returns true if events does not exist' do
          expect(@agent.send(:store_payload!, @agent.events, 'comment' => 'othervalue', 'id' => 98765)).to be true
        end
      end
    end

    describe 'previous_payloads' do
      before do
        Event.create payload: { 'comment' => 'some value'}, agent: @agent
        Event.create payload: { 'comment' => 'another value'}, agent: @agent
        Event.create payload: { 'comment' => 'other comment'}, agent: @agent
      end


      it 'returns a list of old events limited by received events' do
        expect(@agent.events.count).to eq(3)
        expect(@agent.send(:previous_payloads, 1).count).to eq(3)
      end


      it 'returns nil when mode is not on_change' do
        @agent.options['mode'] = 'all'
        expect(@agent.send(:previous_payloads, 1)).to be nil
      end
    end
  end

  describe 'build_default_options' do
    before do
      @opts = {
        "subdomain": "foo",
        "account_email": "name@example.com",
        "api_token": "token123",
        'expected_update_period_in_days' => '2',
        'mode' => 'on_change',
        'retrieve_assignee' => 'false',
        'retrieve_ticket' => 'false',
        'retrieve_group' => 'false'
      }
      @agent = Agents::ZendeskSatisfactionRatingsAgent.new(:name => 'Another agent', :options => @opts)
      @agent.user = users(:bob)

    end

    it 'generate a correct url option' do
      @agent.send(:build_default_options)

      expected = "https://foo.zendesk.com/api/v2/satisfaction_ratings.json"
      expect(@agent.options['url']).to eq(expected)

      @agent.options['filter'] = "sort_order=desc"
      @agent.send(:build_default_options)

      expected = "https://foo.zendesk.com/api/v2/satisfaction_ratings.json?sort_order=desc"
      expect(@agent.options['url']).to eq(expected)
    end

    context 'when use_oauth is false' do
      before do
        @agent.send(:build_default_options)
      end

      it 'generate a correct basic_auth option' do
        expected = "name@example.com/token:token123"
        expect(@agent.options['basic_auth']).to eq(expected)
      end

      it 'does not generate a headers option' do
        expect(@agent.options['headers']).to be nil
      end
    end

    context 'when use_oauth is true' do
      before do
        @agent.options['use_oauth'] = 'true'
        @agent.send(:build_default_options)
      end

      it 'generate a correct headers option' do
        expected = { "Authorization" => "Bearer token123" }
        expect(@agent.options['headers']).to eq(expected)
      end

      it 'does not generate a basic_auth option' do
        expect(@agent.options['basic_auth']).to be nil
      end
    end
  end

end
