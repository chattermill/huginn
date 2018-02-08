require 'rails_helper'

describe SurveyMonkeyParser do
  let(:data) do
    file = File.read(Rails.root.join('spec', 'fixtures', 'surveymonkey', 'survey_details.json'))
    JSON.parse(file)
  end
  let(:service) { described_class.new(data) }

  describe '#parse_responses' do
    let(:responses) { service.parse_responses }
    let(:response) { responses.first }

    it "parses all responses" do
      expect(responses.size).to eq(2)
    end

    context 'when use_weights is false' do
      it "returns an average score from text attribute" do
        expect(response.key?('score')).to be true
        expect(response['score']).to eq(1)
      end
    end

    context 'when use_weights is true' do
      let(:service) { described_class.new(data.merge('use_weights' => true)) }

      it "returns an average score from weight attribute" do
        expect(response.key?('score')).to be true
        expect(response['score']).to eq(2)
      end
    end

    it "returns a comment attribute" do
      expect(response.key?('comment')).to be true
      expect(response['comment']).to eq("Dreadful customer service")
    end

    it "returns the response id attribute" do
      expect(response.key?('id')).to be true
      expect(response['id']).to eq("5487508380")
    end

    it "returns a survey_id attribute" do
      expect(response.key?('survey_id')).to be true
      expect(response['survey_id']).to eq("60926882")
    end

    it "returns a date_created attribute" do
      expect(response.key?('date_created')).to be true
      expect(response['date_created']).to eq("2018-02-08T08:35:49+00:00")
    end

    it "returns a collector_id attribute" do
      expect(response.key?('collector_id')).to be true
      expect(response['collector_id']).to eq("98090338")
    end

    it "returns a custom_variables attribute" do
      expected = {
        "key" => "some value"
      }
      expect(response.key?('custom_variables')).to be true
      expect(response['custom_variables']).to eq(expected)
    end

    it "returns a analyze_url attribute" do
      expect(response.key?('analyze_url')).to be true
      expect(response['analyze_url']).to eq("http://www.example.com")
    end

    it "returns a language attribute" do
      expect(response.key?('language')).to be true
      expect(response['language']).to eq("en")
    end

    it "returns a full_response attribute with all response answers" do
      expected = {
        '759363655' => {
          id: '759363655',
          family: 'single_choice',
          subtype: 'vertical',
          question: 'Did we answer your question?',
          answers: {
            'Did we answer your question?' => 'No'
          }
        },
        '759363654' => {
          id: '759363654',
          family: 'matrix',
          subtype: 'rating',
          question: 'In the following area, how would you evaluate the agent who answered you?',
          answers: {
            'Enthusiasm' => 'Very bad 0',
            'Professionalism' => 'Very bad 0',
            'Understanding of your needs' => 'Good 3',
            'Clarity of answer' => 'Very bad 0',
            'Patience' => 'Very bad 0'
          }
        },
        '759363658' => {
          id: '759363658',
          family: 'open_ended',
          subtype: 'essay',
          question: 'How could we improve the service?',
          answers: {
            'How could we improve the service?' => 'Dreadful customer service'
          }
        },
        '759363659' => {
          id: '759363659',
          family: 'open_ended',
          subtype: 'essay',
          question: 'What would be your suggestions to improve Vivastreet ?',
          answers: {
            'What would be your suggestions to improve Vivastreet ?' => 'Get new staff that are not useless '
          }
        },
        '759363657' => {
          id: '759363657',
          family: 'open_ended',
          subtype: 'multi',
          question: 'If you wish, enter your contact information below so we can contact you if necessary:',
          answers: {
            'Email address' => 'me@foo.com',
            'Telephone number' => '12345'
          }
        },
      }
      expect(response.key?('full_response')).to be true
      expect(response['full_response']).to eq(expected)
    end
  end
end
