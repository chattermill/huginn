require 'rails_helper'

describe Agents::SurveyMonkeyAgent, :vcr do
  before do
    VCR.insert_cassette 'survey_monkey', record: :new_episodes

    @opts = {
      'api_token' => 'token123',
      'survey_ids' => '120641887',
      'expected_update_period_in_days' => '2',
      'mode' => 'on_change',
      'page' => '1',
      'per_page' => '5',
      'guess_mode' => 'true',
      'use_weights' => 'false'
    }
    @agent = Agents::SurveyMonkeyAgent.new(:name => 'SM test', :options => @opts)
    @agent.user = users(:bob)
    @agent.save!
  end

  after do
    VCR.eject_cassette
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

  describe '#http_method' do
    it 'returns valid uri' do
      expect(@agent.http_method).to eq('get')
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

    it 'should validate presence of api_token' do
      @agent.options['api_token'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of survey_ids' do
      @agent.options['survey_ids'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of expected_update_period_in_days' do
      @agent.options['expected_update_period_in_days'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of page' do
      @agent.options['page'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate presence of per_page' do
      @agent.options['per_page'] = ''
      expect(@agent).not_to be_valid
    end

    it 'should validate mode value' do
      @agent.options['mode'] = 'xx'
      expect(@agent).not_to be_valid
    end

    it 'should validate uniqueness_look_back be greater than 0' do
      @agent.options['uniqueness_look_back'] = '0'
      expect(@agent).not_to be_valid
    end

    context 'when guess_mode is false' do
      before do
        @agent.options['guess_mode'] = 'false'
      end

      it 'should validate score_question_ids is present' do
        @agent.options['score_question_ids'] = ''
        expect(@agent).not_to be_valid
      end

      it 'should validate comment_question_ids is present' do
        @agent.options['comment_question_ids'] = ''
        expect(@agent).not_to be_valid
      end
    end
  end

  describe '#check' do
    context 'when there is not another agent running' do
      it 'emits events' do
        expect { @agent.check }.to change { Event.count }.by(5)
      end

      it 'does not emit duplicated events ' do
        @agent.check
        @agent.events.last.destroy

        expect { @agent.check }.to change { Event.count }.by(1)
        expect(@agent.events.count).to eq(5)
      end

      it 'emits correct payload' do
        @agent.check
        payload = @agent.events.first.payload
        expected = {
          "score"=>9,
          "comment"=>  "Me parece un servicio muy útil, hace más fácil viajar, por los horarios, la comodidad y la rapidez. Además la aplicación/ página web tiene una buena usabilidad. ",
          "id"=>"6679245053",
          "survey_id"=>"120641887",
          "date_created"=>"2018-02-07T15:50:38+00:00",
          "collector_id"=>"160345859",
          "custom_variables"=>{"hid"=>"17119010"},
          "analyze_url"=> "https://www.surveymonkey.com/analyze/browse/luifTxpMqjC5UdZnocdTgJ8Et4kYkeCcv_2BkKNNFhby8_3D?respondent_id=6679245053",
          "language"=>"es",
          "full_response"=> {
            "149398100"=> {
              "id"=>"149398100",
              "family"=>"matrix",
              "subtype"=>"rating",
              "question"=>
               "¿Qué tan probable es que recomiendes BlaBlaCar a tus amigos o compañeros de trabajo?<br><br><em>0 significa \"nada probable\"</em><br><em>10 significa \"muy probable\"<br><br></em>",
              "answers"=>{""=>"9"}
            },
            "149398098"=> {
              "id"=>"149398098",
              "family"=>"open_ended",
              "subtype"=>"essay",
              "question"=>"¿Qué es lo que hace realmente bien BlaBlaCar?",
              "answers"=> {
                "¿Qué es lo que hace realmente bien BlaBlaCar?" => "Me parece un servicio muy útil, hace más fácil viajar, por los horarios, la comodidad y la rapidez. Además la aplicación/ página web tiene una buena usabilidad. "
              }
            },
            "149398096"=> {
              "id"=>"149398096",
              "family"=>"single_choice",
              "subtype"=>"vertical",
              "question"=>"¿Por qué realizaste tu último viaje en coche compartido?",
              "answers"=> {
                "¿Por qué realizaste tu último viaje en coche compartido?"=> "Para visitar a amigos"
              }
            }
          }
        }
        expect(payload).to eq(expected)
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

      it 'changes memory in_process to false when an error raised' do
        mock(@agent).check.once {
          raise "error"
        }
        expect {
          @agent.check
        }.to raise_error(RuntimeError)
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
    it 'should generate a correct survey_ids enum' do
      @agent.options['survey_ids'] = '120641887 , 120641889 '
      expect(@agent.send(:survey_ids)).to eq(['120641887','120641889'])
    end

    context 'build a correct survey hash' do
      context 'when guess_mode is true' do
        before do
          @survey = @agent.send(:build_survey, '120641887')
        end

        it 'should have the responses key' do
          expect(@survey.key?('responses')).to be true
        end

        it 'should have the use_weights key' do
          expect(@survey.key?('use_weights')).to be true
        end
      end

      context 'when guess_mode is false' do
        before do
          @agent.options['guess_mode'] = false
          @agent.options['score_question_ids'] = '149398100'
          @agent.options['comment_question_ids'] = '149398098'
          @survey = @agent.send(:build_survey, '120641887')
        end

        it 'should have the responses key' do
          expect(@survey.key?('responses')).to be true
        end

        it 'should have the use_weights key' do
          expect(@survey.key?('use_weights')).to be true
        end

        it 'should generate the correct score_question_ids' do
          expect(@survey.key?('score_question_ids')).to be true
          expect(@survey['score_question_ids']).to eq('149398100')
        end

        it 'should generate the correct comment_question_ids' do
          expect(@survey.key?('comment_question_ids')).to be true
          expect(@survey['comment_question_ids']).to eq('149398098')
        end
      end
    end

    it 'should generate a correct header' do
      expected = { "Authorization" => "bearer token123" }
      expect(@agent.send(:headers)).to eq(expected)
    end
  end
end
