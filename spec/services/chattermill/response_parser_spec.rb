require 'rails_helper'

describe Chattermill::ResponseParser do
  let(:data) do
    {
     "organization_subdomain"=>"xyz",
     "id"=>"",
     "comment"=>"Good service",
     "score"=>"3",
     "data_type"=>"nps",
     "data_source"=>"nps_survey",
     "dataset_id"=>"1",
     "created_at"=>"2018-02-03 00=>00:00",
     "user_meta" => {
       "age"=>{"type"=>"text", "name"=>"Age", "value"=>"25"}
     },
     "segments" => {
       "segment_id"=>{"type"=>"text", "name"=>"Sample Id", "value"=>"Segment value"}
     },
     "extra_fields"=>{"some_key" => "some value"},
     "mappings"=>{},
     "bucketing"=>{},
     "emit_events_radio"=>"true",
     "emit_events"=>"true",
     "expected_receive_period_in_days"=>"1",
     "send_batch_events_radio"=>"false",
     "send_batch_events"=>"false",
     "max_events_per_batch"=>"2"
   }
  end

  let(:service) { described_class.new(data) }

  describe '#parse' do
    context 'with valid data' do
      it "return a comment field" do
        expect(service.parse.fetch('comment')).to eq("Good service")
      end

      it "return a score field" do
        expect(service.parse.fetch('score')).to eq("3")
      end

      it "return a data_type field" do
        expect(service.parse.fetch('data_type')).to eq("nps")
      end

      it "return a data_source field" do
        expect(service.parse.fetch('data_source')).to eq("nps_survey")
      end

      it "return a created_at field" do
        expect(service.parse.fetch('created_at')).to eq("2018-02-03 00=>00:00")
      end

      it "return a user_meta field" do
        expected = {
          "age"=>{"type"=>"text", "name"=>"Age", "value"=>"25"}
        }

        expect(service.parse.fetch('user_meta')).to eq(expected)
      end

      it "return a segments field" do
        expected = {
          "segment_id"=>{"type"=>"text", "name"=>"Sample Id", "value"=>"Segment value"}
        }

        expect(service.parse.fetch('segments')).to eq(expected)
      end

      it "return a dataset_id field" do
        expect(service.parse.fetch('dataset_id')).to eq("1")
      end

      it "return extra fields" do
        expect(service.parse.fetch("some_key")).to eq("some value")
      end
    end

    context 'with no valid data' do
      it "does not return a comment field when comment is not present" do
        data["comment"] =  ""
        expect(service.parse.key?('comment')).to be false
      end

      it "does not return a score field when score is not present" do
        data["score"] =  ""
        expect(service.parse.key?('score')).to be false
      end

      it "does not return a data_type field when data_type is not present" do
        data["data_type"] =  ""
        expect(service.parse.key?('data_type')).to be false
      end

      it "does not return a data_source field when data_source is not present" do
        data["data_source"] =  ""
        expect(service.parse.key?('data_source')).to be false
      end

      it "does not return a created_at field when created_at is not present" do
        data["created_at"] =  ""
        expect(service.parse.key?('created_at')).to be false
      end

      it "does not return a user_meta field when user_meta is not present" do
        data["user_meta"] =  ""
        expect(service.parse.key?('user_meta')).to be false
      end

      it "does not return a segments field when segments is not present" do
        data["segments"] =  ""
        expect(service.parse.key?('segments')).to be false
      end

      it "does not return a dataset_id field when dataset_id is not present" do
        data["dataset_id"] =  ""
        expect(service.parse.key?('dataset_id')).to be false
      end

      it "does return extra fields when extra_fields is not present" do
        data["extra_fields"] =  {}
        expect(service.parse.key?('some_key')).to be false
      end
    end

    context 'with mappings' do
      before do
        data["mappings"] = {
          "score" => {
            "Good, I'm satisfied" => "10",
            "Bad, I'm unsatisfied" => "0"
          },
          "segments.segment_id.value" => {
            "Segment A" => "651",
            "Segment B" => "669"
          }
        }
      end

      it 'returns score with mappings applied' do
        data['score'] = 'Good, I\'m satisfied'
        expect(service.parse.fetch('score')).to eq("10")
      end

      it 'returns original score' do
        data['score'] = 'Bad'
        expect(service.parse.fetch('score')).to eq("Bad")
      end

      it 'returns segments with mappings applied' do
        data['segments']['segment_id']['value'] = 'Segment A'
        expected = { "segment_id"=>{"type"=>"text", "name"=>"Sample Id", "value"=>"651"} }
        expect(service.parse.fetch('segments')).to eq(expected)
      end

      it 'returns original segments' do
        data['segments']['segment_id']['value'] = 'Segment X'
        expected = { "segment_id"=>{"type"=>"text", "name"=>"Sample Id", "value"=>"Segment X"} }

        expect(service.parse.fetch('segments')).to eq(expected)
      end
    end

    context 'with bucketings' do
      before do
        data["bucketing"] = {
          "score" => {
            "1-25" => "1",
            "26-50" => "3",
            "51-75" => "4",
            "76-100" => "5"
          },
          "segments.tc.value" => {
            "1-25" => "First 25",
            "26-50" => "26 - 50",
            "51-100" => "51 - 100",
            "100+" => "More than 100"
          }
        }
      end

      context 'with single keys' do
        it 'returns score with bucketing applied' do
          data['score'] = '54'

          expect(service.parse.fetch('score')).to eq("4")
        end

        it 'returns nil score if does not find range on bucketing def' do
          data['score'] = '0'
          expect(service.parse.fetch('score')).to be nil
        end
      end

      context 'with nested keys' do
        it 'returns segments with bucketing applied' do
          data['segments'] = { "tc"=>{"type"=>"text", "name"=>"Sample Id", "value"=>"101"} }
          expected = { "tc"=>{"type"=>"text", "name"=>"Sample Id", "value"=>"More than 100"} }

          expect(service.parse.fetch('segments')).to eq(expected)
        end

        it 'returns nil value if does not find range on bucketing def' do
          data['segments'] = { "tc"=>{"type"=>"text", "name"=>"Sample Id", "value"=>"0"} }
          expected = { "tc"=>{"type"=>"text", "name"=>"Sample Id", "value"=>nil} }

          expect(service.parse.fetch('segments')).to eq(expected)
        end
      end
    end
  end
end
