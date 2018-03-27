require 'rails_helper'

describe Agents::UsabillaAgent do
  before do

    @opts = {
      'access_key' => '1234567889',
      'secret_key' => 'token123',
      'expected_update_period_in_days' => '1',
      'mode' => 'on_change',
      'retrieve_buttons' => 'false',
      'retrieve_apps' => 'false',
      'retrieve_emails' => 'false',
      'retrieve_campaigns' => 'false',
      'buttons_to_retrieve' => '*',
      'emails_to_retrieve' => '*',
      'apps_to_retrieve' => '*',
      'campaigns_to_retrieve' => '*',
      'days_ago' => '1'    }

    @agent = Agents::UsabillaAgent.new(:name => 'My agent', :options => @opts)
    @agent.user = users(:bob)
    @agent.save!

    stub_request(:get, /data.usabilla.com\/live\/websites\/campaign/)
      .to_return(body: File.read(Rails.root.join("spec/data_fixtures/usabilla/campaigns.json")), status: 200)
    stub_request(:get, /data.usabilla.com\/live\/websites\/button/)
      .to_return(body: File.read(Rails.root.join("spec/data_fixtures/usabilla/buttons.json")), status: 200)
    stub_request(:get, /data.usabilla.com\/live\/apps/)
      .to_return(body: File.read(Rails.root.join("spec/data_fixtures/usabilla/apps.json")), status: 200)
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

    it 'should validate presence of access_key' do
      @agent.options['access_key'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of secret_key' do
      @agent.options['secret_key'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of retrieve_buttons' do
      @agent.options['retrieve_buttons'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of retrieve_apps' do
      @agent.options['retrieve_apps'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of retrieve_emails' do
      @agent.options['retrieve_emails'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of retrieve_campaigns' do
      @agent.options['retrieve_campaigns'] = ''
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

  describe '#check' do
    context 'when retrieve_campaigns is true' do
      before do
        @agent.options['retrieve_campaigns'] = true
      end

      it 'emits events' do
        expect { @agent.check }.to change { Event.count }.by(8)
      end

      it 'does not emit duplicated events ' do
        @agent.check
        @agent.events.last.destroy

        expect(@agent.events.count).to eq(7)
        expect(@agent.tokens.count).to eq(7)
        expect { @agent.check }.to change { Event.count }.by(1)
        expect(@agent.events.count).to eq(8)
        expect(@agent.tokens.count).to eq(8)
      end

      it 'emits correct payload' do
        @agent.check
        payload = @agent.events.last.payload
        expected = {
          'comment' => "J'ai l'impression de manger au restaurant tout les jours de la semaine",
          'score' => 10,
          'location' => 'Charleroi, Belgium',
          'id' => '5a911d43f63e5d1c02000c50',
          'custom' => [],
          'public_url' => nil,
          'button_id' => nil,
          'created_at' => '2018-02-24T08:07:31.3Z',
          'email' => nil,
          'raw_data' => {
            "id" => "5a911d43f63e5d1c02000c50",
            "userAgent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36 Edge/16.16299",
            "location" => "Charleroi, Belgium",
            "date" => "2018-02-24T08:07:31.3Z",
            "campaignId" => "59e0cbe2acd8122c266b8d42",
            "customData" => {
                "customer_id" => "555528"
            },
            "data" => {
                "comment_3" => "J'ai l'impression de manger au restaurant tout les jours de la semaine",
                "nps" => 10
            },
            "url" => "https://www.hellofresh.be/loyalty/status/?redirectedFromAccountArea=true",
            "time" => 54994
          }
        }

        expect(payload).to eq(expected)
      end
    end

    context 'when retrieve_buttons is true' do
      before do
        @agent.options['retrieve_buttons'] = true
      end

      it 'emits events' do
        expect { @agent.check }.to change { Event.count }.by(5)
      end

      it 'does not emit duplicated events ' do
        @agent.check
        @agent.events.last.destroy

        expect(@agent.events.count).to eq(4)
        expect(@agent.tokens.count).to eq(4)
        expect { @agent.check }.to change { Event.count }.by(1)
        expect(@agent.events.count).to eq(5)
        expect(@agent.tokens.count).to eq(5)
      end

      it 'emits correct payload' do
        @agent.check
        payload = @agent.events.last.payload
        expected = {
          'comment' => "i cannot log in",
          'score' => 1,
          'location' => 'Huntsville, AL, United States',
          'id' => '5a90e35b2c1f537f870f925c',
          'custom' => {
              "please_select_a_topi" => "bug"
          },
          'public_url' => "https://www.usabilla.com/feedback/item/147f1c0d301ef80ea557c66e3cf421cee39f76e8",
          'button_id' => '77ef9e751258',
          'created_at' => '2018-02-24T04:00:36.866Z',
          'email' => "",
          'raw_data' => {
            "id" => "5a90e35b2c1f537f870f925c",
            "userAgent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 11_0_2 like Mac OS X) AppleWebKit/604.1.34 (KHTML, like Gecko) CriOS/64.0.3282.112 Mobile/15A421 Safari/604.1",
            "comment" => "i cannot log in",
            "commentTranslated" => "",
            "commentTranslatedFrom" => "",
            "location" => "Huntsville, AL, United States",
            "browser" => {
                "name" => "Chrome Mobile iOS",
                "version" => "64.0.3282.112",
                "os" => "iOS",
                "devicetype" => "Mobile Phone"
            },
            "date" => "2018-02-24T04:00:36.866Z",
            "custom" => {
                "please_select_a_topi" => "bug"
            },
            "email" => "",
            "image" => "http://u4w-screenshots-production.s3.amazonaws.com/5a90e35b2c1f537f870f925c/full_image",
            "labels" => [
                "bug"
            ],
            "nps" => 0,
            "publicUrl" => "https://www.usabilla.com/feedback/item/147f1c0d301ef80ea557c66e3cf421cee39f76e8",
            "rating" => 1,
            "buttonId" => "77ef9e751258",
            "tags" => [],
            "url" => "https://www.hellofresh.com/customer/account/login/?default=true&continue=%2Fmy-account%2Fdeliveries%2Fmenu%2F2018-W09%3Fdefault%3Dtrue",
            "Bucket" => "u4w-screenshots-production"
          }
        }

        expect(payload).to eq(expected)
      end
    end

    context 'when retrieve_apps is true' do
      before do
        @agent.options['retrieve_apps'] = true
      end

      it 'emits events' do
        expect { @agent.check }.to change { Event.count }.by(5)
      end

      it 'does not emit duplicated events ' do
        @agent.check
        @agent.events.last.destroy

        expect(@agent.events.count).to eq(4)
        expect(@agent.tokens.count).to eq(4)
        expect { @agent.check }.to change { Event.count }.by(1)
        expect(@agent.events.count).to eq(5)
        expect(@agent.tokens.count).to eq(5)
      end

      it 'emits correct payload' do
        @agent.check
        payload = @agent.events.last.payload
        expected = {
          'comment' => "Won't honor my Groupon.",
          'score' => 1,
          'location' => 'Grand Prairie, United States',
          'id' => '5a91907fada3421c060000fd',
          'custom' => {},
          'public_url' => nil,
          'button_id' => nil,
          'created_at' => '2018-02-24T16:19:12.244Z',
          'email' => nil,
          'raw_data' => {
            "id" => "5a91907fada3421c060000fd",
            "date" => "2018-02-24T16:19:12.244Z",
            "timestamp" => "1519489151",
            "appId" => "5912eac9ed3925f77aef5e4c",
            "appName" => "HelloFresh",
            "appVersion" => "2160",
            "deviceName" => "iPhone7,2",
            "osName" => "ios",
            "osVersion" => "10.2.1",
            "language" => "en",
            "rooted" => false,
            "freeMemory" => 0,
            "totalMemory" => 0,
            "freeStorage" => 17722940,
            "totalStorage" => 118880884,
            "orientation" => "Portrait",
            "batteryLevel" => 0.86,
            "geoLocation" => {
                "country" => "US",
                "region" => "TX",
                "city" => "Grand Prairie",
                "lat" => 32.6606,
                "lon" => -97.0249
            },
            "location" => "Grand Prairie, United States",
            "connection" => "WiFi",
            "customData" => nil,
            "data" => {
                "comment_app" => nil,
                "comment_service" => "Won't honor my Groupon.",
                "email" => "dscott1731@yahoo.com",
                "feedback_choice" => [
                    "Bug"
                ],
                "mood" => 1
            },
            "screenshot" => "http://u4a-screenshots-production.s3.amazonaws.com/live/media/5a/91/5a91907fada3421c060000fd/screenshot",
            "screensize" => "375x667"
          }
        }

        expect(payload).to eq(expected)
      end
    end

    context 'without any response' do
      it 'does not emit events' do
        expect { @agent.check }.to change { Event.count }.by(0)
      end
    end
  end

  describe 'helpers' do
    describe 'retrieve_events' do
      it 'does not retrieve any events' do
        expect(@agent.send(:retrieve_events)).to eq([])
      end

      it 'retrieve buttons items correctly' do
        @agent.options['retrieve_buttons'] = true
        expect(@agent.send(:retrieve_events).size).to eq(5)
      end

      it 'retrieve apss items correctly' do
        @agent.options['retrieve_apps'] = true
        expect(@agent.send(:retrieve_apps).size).to eq(5)
      end

      it 'retrieve campaigns items correctly' do
        @agent.options['retrieve_campaigns'] = true
        expect(@agent.send(:retrieve_campaigns).size).to eq(8)
      end
    end

    it 'retrieve_buttons? returns values correctly' do
      expect(@agent.send(:retrieve_buttons?)).to be false

      @agent.options['retrieve_buttons'] = ''
      expect(@agent.send(:retrieve_buttons?)).to be nil

      @agent.options['retrieve_buttons'] = true
      expect(@agent.send(:retrieve_buttons?)).to be true
    end

    it 'retrieve_apps? returns values correctly' do
      expect(@agent.send(:retrieve_apps?)).to be false

      @agent.options['retrieve_apps'] = ''
      expect(@agent.send(:retrieve_apps?)).to be nil

      @agent.options['retrieve_apps'] = true
      expect(@agent.send(:retrieve_apps?)).to be true
    end

    it 'retrieve_campaigns? returns values correctly' do
      expect(@agent.send(:retrieve_campaigns?)).to be false

      @agent.options['retrieve_campaigns'] = ''
      expect(@agent.send(:retrieve_campaigns?)).to be nil

      @agent.options['retrieve_campaigns'] = true
      expect(@agent.send(:retrieve_campaigns?)).to be true
    end

    it 'retrieve_emails? returns values correctly' do
      expect(@agent.send(:retrieve_emails?)).to be false

      @agent.options['retrieve_emails'] = ''
      expect(@agent.send(:retrieve_emails?)).to be nil

      @agent.options['retrieve_emails'] = true
      expect(@agent.send(:retrieve_emails?)).to be true
    end

    describe 'usabilla_response_to_event' do
      it 'should generate the correct payload' do
        response = OpenStruct.new
        expected = {
          comment: nil,
          score: nil,
          location: nil,
          id: nil,
          custom: nil,
          public_url: nil,
          button_id: nil,
          created_at: nil,
          email: nil,
          raw_data: nil
        }
        expect(@agent.send(:usabilla_response_to_event, response)).to eq(expected)
      end
    end

    it 'should extract the correct comment' do
      response = OpenStruct.new comment: 'Hello'
      expect(@agent.send(:extract_comment, response)).to eq('Hello')

      response = OpenStruct.new "data": { "comment_service" => 'Hello world'}
      expect(@agent.send(:extract_comment, response)).to eq('Hello world')

      response = OpenStruct.new "data": { "comment_service" => '', "comment_last" => "Last comment"}
      expect(@agent.send(:extract_comment, response)).to eq('Last comment')

      response = OpenStruct.new "data": { "comment_service" => ''}
      expect(@agent.send(:extract_comment, response)).to be nil
    end

    it 'should extract the correct score' do
      response = OpenStruct.new
      expect(@agent.send(:extract_score, response)).to be nil

      response = OpenStruct.new data: { rating: 1}
      expect(@agent.send(:extract_score, response)).to be nil

      response = OpenStruct.new rating: 10
      expect(@agent.send(:extract_score, response)).to be 10

      response = OpenStruct.new data: { mood: 5}
      expect(@agent.send(:extract_score, response)).to be 5

      response = OpenStruct.new data: { nps: 8}
      expect(@agent.send(:extract_score, response)).to be 8

      response = OpenStruct.new data: { mood: 5, nps: 8}
      expect(@agent.send(:extract_score, response)).to be 5
    end
  end
end
