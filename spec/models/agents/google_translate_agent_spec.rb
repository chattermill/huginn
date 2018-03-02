require 'rails_helper'

describe Agents::GoogleTranslateAgent, :vcr do
  before do

    @opts = {
      'to' => 'en',
      'from' => 'es',
      'expected_receive_period_in_days' => 1,
      'merge' => 'false',
      'content' => {
        'comment' => '{{comment}}'
      }
    }

    @checker = Agents::GoogleTranslateAgent.new(:name => 'My agent', :options => @opts)
    @checker.user = users(:jane)
    @checker.save!

    @event = Event.new
    @event.agent = agents(:jane_weather_agent)
    @event.payload = {
      'comment' => "Hola desde aquí"
    }

    stub.proxy(ENV).[](anything)
    stub(ENV).[]('GOOGLE_TRANSLATE_API_KEY') { 'token123' }
  end

  describe "#working?" do
    it "checks if events have been received within expected receive period" do
      expect(@checker).not_to be_working
      Agents::GoogleTranslateAgent.async_receive @checker.id, [@event.id]
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

    it "should validate presence of 'to' key" do
      @checker.options[:to] = ""
      expect(@checker).not_to be_valid
    end

    it "should validate presence of expected_receive_period_in_days key" do
      @checker.options[:expected_receive_period_in_days] = nil
      expect(@checker).not_to be_valid
    end

    it "should validate presence of merge" do
      @checker.options[:merge] = nil
      expect(@checker).not_to be_valid
    end
  end

  describe '#check' do
    it 'emit events' do
      expect {
        @checker.check
      }.to change { Event.count }.by(1)
    end

    it 'guess the source language' do
      @checker.options['from'] =''
      @checker.options['content'] = { 'comment' => 'comment allez-vous' }
      @checker.check

      expected = { 'comment' => 'how are you' }
      expect(@checker.events.first.payload).to eq(expected)
    end

    context 'when merge is false' do
      it 'emit the correct payload' do
        @checker.options['content'] = {
          'subject' => 'Hola',
          'message' => 'Hola Mundo'
        }
        @checker.check

        expected = {
          'subject' => 'Hello',
          'message' => 'Hello World'
        }
        expect(@checker.events.first.payload).to eq(expected)
      end


    end

    context 'when merge is true' do
      before do
        @checker.options['merge'] = 'true'
      end

      it 'emit the correct payload' do
        @checker.options['content'] = { 'comment' => 'Hola Mundo' }
        @checker.check

        expected = {
          'translated_content' => { 'comment' => 'Hello World' }
        }
        expect(@checker.events.first.payload).to eq(expected)
      end
    end
  end

  describe "#receive" do
    it 'emit events' do
      expect {
        @checker.receive([@event])
      }.to change { Event.count }.by(1)
    end

    it 'guess the source language' do
      @checker.options['from'] = ''
      @checker.receive([@event])

      expected = { 'comment' => 'Hello from here' }
      expect(@checker.events.first.payload).to eq(expected)
    end

    context 'when merge is false' do
      it 'emit the correct payload' do
        @checker.receive([@event])

        expected = { 'comment' => 'Hello from here' }
        expect(@checker.events.first.payload).to eq(expected)
      end
    end

    context 'when merge is true' do
      before do
        @checker.options['merge'] = 'true'
      end

      it 'emit the correct payload' do
        @checker.receive([@event])

        expected = {
          'comment' => 'Hola desde aquí',
          'translated_content' => { 'comment' => 'Hello from here' }
        }
        expect(@checker.events.first.payload).to eq(expected)
      end
    end

    it "can handle multiple events" do
      event1 = Event.new
      event1.agent = agents(:bob_weather_agent)
      event1.payload = {
        comment: "Muy bien"
      }

      expect {
        @checker.receive([@event,event1])
      }.to change { Event.count }.by(2)
    end
  end
end
