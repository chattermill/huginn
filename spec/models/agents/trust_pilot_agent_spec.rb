require 'rails_helper'

describe Agents::TrustPilotAgent do
  before do
    @valid_params = {
      name: "somename",
      options: {
        api_key: 'some_api_key',
        api_secret: 'some_api_secret',
        expected_update_period_in_days: 1,
        business_units_ids: '468302bb00006400050000a5',
        mode: 'on_change',
        access_token: 'some_access_token',
        refresh_token: 'some_refresh_token',
        expires_at: 1.days.from_now
      }
    }

    @checker = Agents::TrustPilotAgent.new(@valid_params)
    @checker.user = users(:jane)
    @checker.save!

    @event = Event.new
    @event.agent = @checker
    @event.payload = {
      message: "hey what are you doing",
      xyz: "do tell more"
    }
  end

  it 'renders the description markdown without errors' do
    expect { @checker.description }.not_to raise_error
  end

  describe "#working?" do
    it "checks if events have been created within expected update period" do
      expect(@checker).not_to be_working
      @event.save!
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

    it "should validate presence of api key" do
      @checker.options[:api_key] = nil
      expect(@checker).not_to be_valid
    end

    it "should validate presence of api secret" do
      @checker.options[:api_secret] = nil
      expect(@checker).not_to be_valid
    end

    it "should validate presence of access token" do
      @checker.options[:access_token] = nil
      expect(@checker).not_to be_valid
    end

    it "should validate presence of refresh token" do
      @checker.options[:refresh_token] = nil
      expect(@checker).not_to be_valid
    end

    it "should validate presence of expires at" do
      @checker.options[:expires_at] = nil
      expect(@checker).not_to be_valid
    end

    it "should validate presence of business_units_ids" do
      @checker.options[:business_units_ids] = nil
      expect(@checker).not_to be_valid
    end

    it "should validate presence of mode" do
      @checker.options[:mode] = nil
      expect(@checker).not_to be_valid
    end

    it "should validate presence of expected_update_period_in_days key" do
      @checker.options[:expected_update_period_in_days] = nil
      expect(@checker).not_to be_valid
    end
  end

  describe "#check" do
    before(:each) do
      stub_request(:get, /reviews$/).to_return(
        body: File.read(Rails.root.join("spec/data_fixtures/trustpilot_reviews.json")),
        status: 200,
        headers: { "Content-Type" => "text/json" }
      )

      stub_request(:post, /refresh/).to_return(
        body: File.read(Rails.root.join("spec/data_fixtures/trustpilot_refresh_token.json")),
        status: 200,
        headers: { "Content-Type" => "text/json" }
      )
    end

    it "emits events per each review" do
      expect { @checker.check }.to change { Event.count }.by(3)
    end

    it "emits review data" do
      expected = { "response_id": "504e1c59000064000227282c",
                   "score": 4,
                   "comment": "De har styr på det, fungerer godt.",
                   "title": "Godt",
                   "language": "da",
                   "created_at": "2012-09-10T16:59:05Z",
                   "updated_at": nil,
                   "company_reply": nil,
                   "is_verified": false,
                   "number_of_likes": 0,
                   "status": "active",
                   "report_data": nil,
                   "compliance_labels": [],
                   "consumer_name": "T.T",
                   "consumer_location": "kbh, DK",
                   "email": "jhon@email.com",
                   "user_reference_id": "123" }.stringify_keys!
      @checker.check
      expect(@checker.events.count).to eq(3)
      expect(@checker.events.first.payload).to eq(expected)
    end

    it "does not duplicate reviews" do
      expect(@checker.events.count).to eq(0)
      @checker.check
      expect(@checker.events.count).to eq(3)
      other_checker = Agents::TrustPilotAgent.first
      other_checker.check
      expect(other_checker.events.count).to eq(3)
    end

    it "refresh token if expired" do
      expect(@checker.options['expires_at'].to_datetime > Time.now).to be true

      three_days_from_now = 3.days.from_now
      stub(Time).now { three_days_from_now }
      expect(@checker.options['expires_at'].to_datetime > Time.now).to be false

      @checker.check
      @checker.save!

      expect(@checker.reload.options['refresh_token']).to eq('EEfgro79v00TIhKMA9uvVqFmlGM6zN9m')
      expect(@checker.options['access_token']).to eq('NOnI0OxB8S5fqbDZoYP17maEsYSg')
      expect(@checker.options['expires_at'].to_datetime > Time.now).to be true
    end
  end
end
