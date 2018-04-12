require 'rails_helper'

describe Agents::GooglePlayReviewsAgent do
  before do

    @opts = {
      'service_account_json' => '{
        "type": "service_account",
        "project_id": "api-123456",
        "private_key_id": "12345",
        "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCvCK6YcU0AsWZL\nAhm38YSXORYsifJYDOwBtmm7imN0+Y1q7kp1LttKAk9JrdMI/7JyFDIXKd2csBIS\n/ad/Eopmuykzs5jt9I0GpRasMYNqegcyvbMCFKSx93v50WtQ/sSWpjmDvMx4Fuc9\nvb7zKt/KJYuHGw8MwKRu0gabHHI5vHRJtam5wpZXAjHw5M+fIY6SRVwas9W/7V4I\nGjN/Lf+aQwvTzGjkSig5VWYujj9XaAbD7KIS8aYInoAO+yYE0fiXlm4dvuNl40Yo\nW3NS6ae/a6X3/nHqb+dQIiSrFsU95WN2hIKw7lizVX/KcEjQGZuBz2g9p7Uk07zn\nYk9sO1IFAgMBAAECggEAE55nwX77mE8KDfDBlLhNugyEQ4A/yWZDYsrBLavsi204\nUGq+rkVO/4vkOrgwzhKo+/AAAAAAAAAAmQDU8B2SJUMnsluYUd2mG/9PnAPdvMbK\nPUH9iUdqkWcRvpXeT0ELJG6jxjQYgAJjL2yv9T4SQOx15/IcvPtvwtsoMeUdmYJq\nTB1yfA9eVYOfw1eoHL3VSk7KQIq7iHrNgHZPNbTvEbLBdyr4rPVS+KF7QIMFNasm\ndjJGG74Vla60JjIg/PDOfS8z5Lzt+ut9JGxBIdsY9cLocu/BBBpmnMu1TUFUfbuN\nd2VFR81l0NmDng7ipxhb/29wAFdHYLiRAXK+idpFsQKBgQDeijwHxQnTbei3KIn+\nIxTfTwu4+xI70U38zRxujmMqAAdap05uz04EPtKWwK3/egjO8BrrRzr6vR/6nXfE\nku/WU6hiy8WUYM12RQtMQDEBgZ36VM4BJNjCijYAHOQhdP4aFZ4kVJ0W65zz0zJg\nqowjTr0HqYLuCo6MsTVTeopMtQKBgQDJWeViuGAN3lLXh1GO99AAAAAAAAAAAAAA\nk2mbXSdVlbVxoJjr5EgtWtRdEaK/sDGWCFR+6/pfFf1Ca+a/zsiMMUdENNG4V5FW\nBTDj4xT5Ql1ZmxRaXkNHMrsLWfYvCOmvMeD8oTW2ai4zpzVg7dXra8iprzibyLJm\njRVHITmSEQKBgC/kX/bsGKk/xg1k1A21TxCf2k38+neVG8uD+NJyIjUvvGVuDBsc\n0hVnz7pRzSBmCu8+DQ0FT1QWz4MH0HaliKf/aQWaBPNhwdXqFfxa9DD2zCDLj2n/\nnAaB6A0uKopouyax8E6xRv1fx29RzE2xZmdS0quLd3nzG6p7mJZWkNzhAoGASKka\nMC/c6eRK/OAmPHONMWRFm2wm8INVd6sEtz48jZQC8EhGJwowSb23WQaeNpJ8smm7\nJDpAFcQ3qpqJoLocgQrfbuuoqt9e4S3qYLJ3xSN/0HA4Pgw6Nx1Fhmkmf/61ZbWY\nPVJnsbZLifRTPPAA+AAAA+AAA/AA/uL2xL5mqiECgYEAoLbets91+Nk5GjEStvbF\nLKEUS5lTuNKpYPF/EP999ee/N61evCYLHyD3TG80+XfrF7OsrNFqx++a+4ThA2pz\nhSMv9WOmfO7H3X6PN1aUE0F3zXdiN1NMqxrygV9S/Gxljfju+eDtmMSiujve6FHi\n0NoyQ+X7+8yeKl1wKBtDabY=\n-----END PRIVATE KEY-----\n",
        "client_email": "appbot-google-play@api-7606179592717496595-892095.iam.gserviceaccount.com",
        "client_id": "123456",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://accounts.google.com/o/oauth2/token",
        "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
        "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/appbot-google-play%40api-7606179592717496595-892095.iam.gserviceaccount.com"
      }',
      'package_name' => 'uk.co.my.app',
      'translation_language' => 'en',
      'expected_update_period_in_days' => '1',
      'mode' => 'on_change',
      "max_results": "100"
    }

    @agent = Agents::GooglePlayReviewsAgent.new(:name => 'My agent', :options => @opts)
    @agent.user = users(:jane)
    @agent.save!

    stub_request(:get, /googleapis.com\/androidpublisher\/v2\/applications/).to_return(
      body: File.read(Rails.root.join("spec/data_fixtures/google_play_reviews.json")),
      headers: {"Content-Type"=> "application/json"},
      status: 200)
    stub_request(:post, /googleapis.com\/oauth2\/v4\/token/).to_return(
      body: '{"token": "123"}',
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

  describe "validation" do
    before do
      expect(@agent).to be_valid
    end

    it "should validate presence of package_name" do
      @agent.options[:package_name] = ""
      expect(@agent).not_to be_valid
    end

    it "should validate presence of expected_update_period_in_days key" do
      @agent.options[:expected_update_period_in_days] = nil
      expect(@agent).not_to be_valid
    end

    it 'should validate service_account_json' do
      @agent.options[:service_account_json] = '{a: 5}'
      expect(@agent).not_to be_valid
    end
  end

  describe "#working?" do
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

  describe '#check' do
    it 'emits events' do
      expect { @agent.check }.to change { Event.count }.by(1)
    end

    it 'emits correct payload' do
      stub(Google::Auth::ServiceAccountCredentials).fetch_access_token! { Google::Auth::ServiceAccountCredentials.new }
      @agent.check

      expected = {
        'author_name' => 'Bob',
        'review_id' => '12345',
        'comment' => 'So much better. Much more intuitive.',
        'original_comment' => 'Original comment',
        'score' => 4,
        'language' => 'en_GB',
        'updated_at' => '2017-09-19T23:00:59.000Z',
        'comments_raw_data' => [
          {
            "developer_comment" => {
              "text" => "developer comment",
              "last_modified" => {
                "seconds" => 1505862059,
                "nanos" => 244000000
              }
            },
            "user_comment" => {
              "text" => "So much better. Much more intuitive.",
              "last_modified" => {
                "nanos" => 244000000,
                "seconds" => 1505862059
              },
              "star_rating" => 4,
              "reviewer_language" => "en_GB",
              "device" => "hero2lte",
              "android_os_version" => 24,
              "app_version_code" => 108060046,
              "app_version_name" => "1.8.6",
              "thumbs_up_count" => 1,
              "thumbs_down_count" => 2,
              "device_metadata" => {
                "product_name" => "hero2lte (Galaxy S7 Edge)",
                "manufacturer" => "Samsung",
                "device_class" => "phone",
                "screen_width_px" => 1200,
                "screen_height_px" => 800,
                "native_platform" => "armeabi-v7a,armeabi,arm64-v8a",
                "screen_density_dpi" => 640,
                "gl_es_version" => 196609,
                "cpu_model" => "Exynos 8890",
                "cpu_make" => "Samsung",
                "ram_mb" => 4096
              },
              "original_text" => "Original comment"
            }
          }
        ]
      }

      expect(@agent.events.last.payload).to eq(expected)
    end

    it 'does not emit duplicated events ' do
      @agent.check
      expect(@agent.events.count).to eq(1)

      expect { @agent.check }.to change { Event.count }.by(0)
      expect(@agent.events.count).to eq(1)
      expect(@agent.tokens.count).to eq(1)
    end
  end

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
    end

    context 'when uniqueness_look_back is present' do
      before do
        @agent.options['uniqueness_look_back'] = 2
      end

      it 'returns a list of old events limited by uniqueness_look_back' do
        expect(@agent.events.count).to eq(3)
        expect(@agent.send(:previous_payloads, 2).count).to eq(2)
      end
    end

    context 'when uniqueness_look_back is not present' do
      it 'returns a list of old events limited by received events' do
        expect(@agent.events.count).to eq(3)
        expect(@agent.send(:previous_payloads, 3).count).to eq(3)
      end
    end

    it 'returns nil when mode is not on_change' do
      @agent.options['mode'] = 'all'
      expect(@agent.send(:previous_payloads, 1)).to be nil
    end
  end
end
