class SurveyMonkeyParser
  attr_reader :survey, :responses

  def initialize(data)
    @survey = Survey.new(data)
    @responses = data.dig('responses', 'data') || []
  end

  def parse_responses
    responses.map do |response|
      ResponseParser.new(response, survey).parse
    end
  end

  class Survey
    def initialize(data)
      @data = data
    end

    def language
      data['language']
    end

    def use_weights
      @use_weights ||= data['use_weights']
    end

    def score_question_ids
      @score_question_ids ||= if data['score_question_ids'].present?
                                data['score_question_ids'].split(',')
                              else
                                questions.select { |q| qualifiable_question?(q) }
                                         .map { |q| q['id'] }
                              end
    end

    def comment_question_ids
      @comment_question_ids ||= if data['comment_question_ids'].present?
                                  data['comment_question_ids'].split(',')
                                else
                                  questions.select { |q| commentable_question?(q) }
                                           .map { |q| q['id'] }
                                end
    end

    def find_question(id)
      questions.find { |q| q['id'] == id }
    end

    private

    attr_reader :data

    def commentable_question?(question)
      question['family'] == 'open_ended' && question['subtype'] == 'essay'
    end

    def qualifiable_question?(question)
      question['family'] == 'matrix' && question['subtype'] == 'rating'
    end

    def questions
      @questions ||= (data['pages'] || []).map { |page| page['questions'] }.flatten
    end

  end

  class Response < OpenStruct

    def score_question
      @score_question ||= find_question(survey.score_question_ids)
    end

    def score_answers
      @score_answers ||= score_question['answers']
    end

    def score_options
      question = survey.find_question(score_question['id'])
      question&.dig('answers', 'choices')
    end

    def comment_question
      @comment_question ||= find_question(survey.comment_question_ids)
    end

    def comment_answers
      comment_question['answers']
    end

    def questions
      @questions ||= pages.map { |page| page['questions'] }.flatten
    end

    private

    def find_question(question_ids)
      question = nil
      question_ids.each do |id|
        question = questions.find { |q| q['id'] == id.strip }
        break if question.present?
      end
      question
    end

  end

  class ResponseParser
    ATTRIBUTES = %w(score comment id survey_id date_created collector_id
                    custom_variables analyze_url language full_response).freeze

    def initialize(data, survey)
      @response = Response.new(data)
      @response.survey = survey
      @survey = survey
    end

    def parse
      ATTRIBUTES.inject({}) { |acc, elem| acc.merge(elem => send(elem)) }
    end

    private

    attr_reader :survey, :response

    delegate :id, :date_created, :survey_id, :collector_id, :custom_variables, :analyze_url, to: :response
    delegate :language, to: :survey

    def score
      return if response.score_question.blank?
      total = response.score_answers.reduce(0) { |sum, answer| sum + (parsed_score_answer(answer["choice_id"]) || 0 ) }
      total.fdiv(response.score_answers.size.nonzero? || 1).round
    end

    def comment
      return if response.comment_question.nil?
      response.comment_answers.map { |answer| answer['text'] }.join("\n")
    end

    def full_response
      questions = response.questions
      questions.each_with_object({}) do |question, hsh|
        details = survey.find_question(question['id']) || {}
        heading = details.present? ? details['headings']&.first['heading'] : ""

        hsh[question['id']] = {
          id: question['id'],
          family: details['family'],
          subtype: details['subtype'],
          question: heading,
          answers: details.present? ? answers_from_question_payload(question, details) : question['answers']
        }

      end
    end

    def answers_from_question_payload(question, details)
      heading = details['headings']&.first['heading']
      rows = details.dig('answers', 'rows')
      choices = details.dig('answers','choices')

      question['answers']&.each_with_object({}) do |a, hsh|
        row = rows&.find { |r| r['id'] == a['row_id'] }['text'] if a['row_id'].present?
        key = row || heading
        value = extract_text_from_answer(a, choices)

        hsh[key] = hsh[key].blank? ? value : "#{hsh[key].to_s}, #{value}"
      end
    end

    def extract_text_from_answer(answer, choices)
      if answer['choice_id'].present?
        choice = choices&.find { |c| c['id'] == answer['choice_id'] }
        choice['text']
      else
        answer['text']
      end
    end

    def parsed_score_answer(choice_id)
      return if response.score_options.blank?
      choice = response.score_options.find { |c| c['id'] == choice_id }

      if survey.use_weights && choice['weight'].present?
        choice['weight']
      else
        choice['text'].gsub(/[^0-9]/, '').to_i
      end
    end

  end


end
