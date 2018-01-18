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

    def commentable_question?(question)
      question['family'] == 'open_ended' && question['subtype'] == 'essay'
    end

    def qualifiable_question?(question)
      question['family'] == 'matrix' && question['subtype'] == 'rating'
    end

    def find_question(id)
      questions.find { |q| q['id'] == id }
    end

    def score_question_ids
      @score_question_ids ||= (data['score_question_ids'] || "").split(',')
    end

    def comment_question_ids
      @comment_question_ids ||= (data['comment_question_ids'] || "").split(',')
    end

    def use_weights
      @use_weights ||= data['use_weights']
    end

    private

    attr_reader :data

    def questions
      @questions ||= (data['pages'] || []).map { |page| page['questions'] }.flatten
    end
  end

  class ResponseParser
    ATTRIBUTES = %w(score comment id survey_id date_created collector_id custom_variables analyze_url language).freeze

    def initialize(data, survey)
      @data = OpenStruct.new(data)
      @survey = survey
    end

    def parse
      ATTRIBUTES.inject({}) { |acc, elem| acc.merge(elem => send(elem)) }
    end

    private

    attr_reader :survey, :data

    delegate :id, :date_created, :survey_id, :collector_id, :custom_variables, :analyze_url, to: :data
    delegate :language, to: :survey

    def score
      return average_score unless score_question.nil?
    end

    def comment
      return parsed_comment_answer unless comment_question.nil?
    end

    def questions
      @questions ||= data['pages']
                     .map { |page| page['questions'] }
                     .flatten
                     .map { |q| q.merge('details' => survey.find_question(q['id'])) }
    end

    def score_question
      if survey.score_question_ids.empty?
        questions.find { |q| survey.qualifiable_question?(q['details']) }
      else
        find_question(survey.score_question_ids)
      end
    end

    def score_options
      score_question.dig('details', 'answers', 'choices')
    end

    def score_answers_given
      score_question['answers']
    end

    def parsed_score_answer(choice_id)
      choice = score_options.find { |c| c['id'] == choice_id }

      if survey.use_weights && choice['weight'].present?
        choice['weight']
      else
        choice['text'].gsub(/[^0-9]/, '').to_i
      end
    end

    def average_score
      total = score_answers_given.reduce(0) { |sum, answer| sum + parsed_score_answer(answer["choice_id"]) }
      total / (score_answers_given.size.nonzero? || 1)
    end

    def comment_question
      if survey.comment_question_ids.empty?
        questions.find { |q| survey.commentable_question?(q['details']) }
      else
        find_question(survey.comment_question_ids)
      end
    end

    def comment_answers_given
      comment_question['answers']
    end

    def parsed_comment_answer
      comments = comment_answers_given.map do |answ|
        answ['text']
      end
      comments.join("\n")
    end

    def find_question(question_ids)
      question = nil
      question_ids.each do |id|
        question = questions.find { |q| q['id'] == id.strip }
        break if question.present?
      end
      question
    end
  end
end
