require 'rails_helper'

describe Agents::S3Agent do
  before(:each) do
    @valid_params = {
                      'mode' => 'read',
                      'access_key_id' => '32343242',
                      'access_key_secret' => '1231312',
                      'watch' => 'false',
                      'bucket' => 'testbucket',
                      'region' => 'us-east-1',
                      'filename' => 'test.txt',
                      'data' => '{{ data }}'
                    }

    @checker = Agents::S3Agent.new(:name => "somename", :options => @valid_params)
    @checker.user = users(:jane)
    @checker.save!
  end

  describe "#validate_options" do
    it "requires the bucket to be set" do
      @checker.options['bucket'] = ''
      expect(@checker).not_to be_valid
    end

    it "requires watch to be present" do
      @checker.options['watch'] = ''
      expect(@checker).not_to be_valid
    end

    it "requires watch to be either 'true' or 'false'" do
      @checker.options['watch'] = 'true'
      expect(@checker).to be_valid
      @checker.options['watch'] = 'false'
      expect(@checker).to be_valid
      @checker.options['watch'] = 'test'
      expect(@checker).not_to be_valid
    end

    it "requires region to be present" do
      @checker.options['region'] = ''
      expect(@checker).not_to be_valid
    end

    it "requires mode to be set to 'read' or 'write'" do
      @checker.options['mode'] = 'write'
      expect(@checker).to be_valid
      @checker.options['mode'] = ''
      expect(@checker).not_to be_valid
    end

    it "requires 'filename' in 'write' mode" do
      @checker.options['mode'] = 'write'
      @checker.options['filename'] = ''
      expect(@checker).not_to be_valid
    end

    it "requires 'data' in 'write' mode" do
      @checker.options['mode'] = 'write'
      @checker.options['data'] = ''
      expect(@checker).not_to be_valid
    end

    it "requires event_type to be empty, 'added', 'modified' or 'removed'" do
      @checker.options['watch'] = 'true'
      @checker.options['event_type'] = ''
      expect(@checker).to be_valid

      %w[added modified removed].each do |type|
        @checker.options['event_type'] = type
        expect(@checker).to be_valid
      end

      @checker.options['event_type'] = 'invalid'
      expect(@checker).not_to be_valid
    end
  end

  describe "#validating" do
    it "validates the key" do
      mock(@checker).client { raise Aws::S3::Errors::SignatureDoesNotMatch.new('', '') }
      expect(@checker.validate_access_key_id).to be_falsy
    end

    it "validates the secret" do
      mock(@checker).buckets { true }
      expect(@checker.validate_access_key_secret).to be_truthy
    end
  end

  it "completes the buckets" do
    mock(@checker).buckets { [OpenStruct.new(name: 'test'), OpenStruct.new(name: 'test2')]}
    expect(@checker.complete_bucket).to eq([{text: 'test', id: 'test'}, {text: 'test2', id: 'test2'}])
  end

  context "#working" do
    it "is working with no recent errors" do
      @checker.last_check_at = Time.now
      expect(@checker).to be_working
    end
  end

  context "#check" do
    context "not watching" do
      it "emits an event for every file" do
        mock(@checker).get_bucket_contents { {"test"=>"231232", "test2"=>"4564545"} }
        expect { @checker.check }.to change(Event, :count).by(2)
        expect(Event.last.payload).to eq({"file_pointer" => {"file"=>"test2", "agent_id"=> @checker.id}})
      end
    end

    context "watching" do
      before(:each) do
        @checker.options['watch'] = 'true'
      end

      it "does not emit any events on the first run" do
        contents = {"test"=>"231232", "test2"=>"4564545"}
        mock(@checker).get_bucket_contents { contents }
        expect { @checker.check }.not_to change(Event, :count)
        expect(@checker.memory).to eq('seen_contents' => contents)
      end

      context "detecting changes" do
        before(:each) do
          contents = {"test"=>"231232", "test2"=>"4564545"}
          mock(@checker).get_bucket_contents { contents }
          expect { @checker.check }.not_to change(Event, :count)
          @checker.last_check_at = Time.now
        end

        it "emits events for removed files" do
          contents = {"test"=>"231232"}
          mock(@checker).get_bucket_contents { contents }
          expect { @checker.check }.to change(Event, :count).by(1)
          expect(Event.last.payload).to eq({"file_pointer" => {"file" => "test2", "agent_id"=> @checker.id}, "event_type" => "removed"})
        end

        it "emits events for modified files" do
          contents = {"test"=>"231232", "test2"=>"changed"}
          mock(@checker).get_bucket_contents { contents }
          expect { @checker.check }.to change(Event, :count).by(1)
          expect(Event.last.payload).to eq({"file_pointer" => {"file" => "test2", "agent_id"=> @checker.id}, "event_type" => "modified"})
        end

        it "emits events for added files" do
          contents = {"test"=>"231232", "test2"=>"4564545", "test3" => "31231231"}
          mock(@checker).get_bucket_contents { contents }
          expect { @checker.check }.to change(Event, :count).by(1)
          expect(Event.last.payload).to eq({"file_pointer" => {"file" => "test3", "agent_id"=> @checker.id}, "event_type" => "added"})
        end

        context "with added event type filter" do
          it "emits only added files" do
            @checker.options['event_type'] = 'added'
            contents = { "test2" => "changed", "test3" => "31231231" }
            mock(@checker).get_bucket_contents { contents }
            expect { @checker.check }.to change(Event, :count).by(1)

            expected = { "file_pointer" => { "file" => "test3", "agent_id" => @checker.id }, "event_type" => "added" }
            expect(Event.last.payload).to eq(expected)
          end
        end

        context "with modified event type filter" do
          it "emits only modified files" do
            @checker.options['event_type'] = 'modified'
            contents = { "test" => "231232", "test2" => "changed", "test3" => "31231231" }
            mock(@checker).get_bucket_contents { contents }
            expect { @checker.check }.to change(Event, :count).by(1)

            expected = { "file_pointer" => { "file" => "test2", "agent_id" => @checker.id }, "event_type" => "modified" }
            expect(Event.last.payload).to eq(expected)
          end
        end

        context "with removed event type filter" do
          it "emits only removed files" do
            @checker.options['event_type'] = 'removed'
            contents = { "test2" => "changed", "test3" => "31231231" }
            mock(@checker).get_bucket_contents { contents }
            expect { @checker.check }.to change(Event, :count).by(1)

            expected = { "file_pointer" => { "file" => "test", "agent_id" => @checker.id }, "event_type" => "removed" }
            expect(Event.last.payload).to eq(expected)
          end
        end

        context "with prefix filter" do
          it "emits events for matching files" do
            @checker.options['prefix'] = 'data'
            contents = { "test2" => "changed", "test3_data" => "31231231", "data_export" => "11111111" }
            mock(@checker).get_bucket_contents { contents }
            expect { @checker.check }.to change(Event, :count).by(1)

            expected = { "file_pointer" => { "file" => "data_export", "agent_id" => @checker.id }, "event_type" => "added" }
            expect(Event.last.payload).to eq(expected)
          end
        end

        context "with suffix filter" do
          it "emits events for matching files" do
            @checker.options['suffix'] = 'export'
            contents = { "test2" => "changed", "export_test3" => "31231231", "data_export" => "11111111" }
            mock(@checker).get_bucket_contents { contents }
            expect { @checker.check }.to change(Event, :count).by(1)

            expected = { "file_pointer" => { "file" => "data_export", "agent_id" => @checker.id }, "event_type" => "added" }
            expect(Event.last.payload).to eq(expected)
          end
        end

        context "with prefix and suffix filter" do
          it "emits events for matching files" do
            @checker.options['prefix'] = 'folder/data'
            @checker.options['suffix'] = '.csv'
            contents = {
              "test2" => "changed",
              "test.csv" => "31231231",
              "folder/data_export.csv" => "11111111",
              "folder/data" => "222",
              "folder/export_data.csv" => "333"
            }

            mock(@checker).get_bucket_contents { contents }
            expect { @checker.check }.to change(Event, :count).by(1)

            expected = { "file_pointer" => { "file" => "folder/data_export.csv", "agent_id" => @checker.id }, "event_type" => "added" }
            expect(Event.last.payload).to eq(expected)
          end
        end
      end

      context "error handling" do
        it "handles AccessDenied exceptions" do
          mock(@checker).get_bucket_contents { raise Aws::S3::Errors::AccessDenied.new('', '') }
          expect { @checker.check }.to change(AgentLog, :count).by(1)
          expect(AgentLog.last.message).to eq("Could not access 'testbucket' Aws::S3::Errors::AccessDenied ")
        end

        it "handles generic S3 exceptions" do
          mock(@checker).get_bucket_contents { raise Aws::S3::Errors::PermanentRedirect.new('', 'error') }
          expect { @checker.check }.to change(AgentLog, :count).by(1)
          expect(AgentLog.last.message).to eq("Aws::S3::Errors::PermanentRedirect: error")
        end
      end
    end
  end

  it "get_io returns a StringIO object" do
    stringio =StringIO.new
    mock_response = mock()
    mock(mock_response).body { stringio }
    mock_client = mock()
    mock(mock_client).get_object(bucket: 'testbucket', key: 'testfile') { mock_response }
    mock(@checker).client { mock_client }
    @checker.get_io('testfile')
  end

  context "#get_bucket_contents" do
    it "returns a hash with the contents of the bucket" do
      mock_response = mock()
      mock(mock_response).contents { [OpenStruct.new(key: 'test', etag: '231232'), OpenStruct.new(key: 'test2', etag: '4564545')] }
      mock_client = mock()
      mock(mock_client).list_objects(bucket: 'testbucket') { [mock_response] }
      mock(@checker).client { mock_client }
      expect(@checker.send(:get_bucket_contents)).to eq({"test"=>"231232", "test2"=>"4564545"})
    end
  end

  context "#client" do
    it "initializes the S3 client correctly" do
      mock_credential = mock()
      mock(Aws::Credentials).new('32343242', '1231312') { mock_credential }
      mock(Aws::S3::Client).new(credentials: mock_credential,
                                      region: 'us-east-1')
      @checker.send(:client)
    end
  end

  context "#event_description" do
    it "should include event_type when watch is set to true" do
      @checker.options['watch'] = 'true'
      expect(@checker.event_description).to include('event_type')
    end

    it "should not include event_type when watch is set to false" do
      @checker.options['watch'] = 'false'
      expect(@checker.event_description).not_to include('event_type')
    end
  end

  context "#receive" do
    before(:each) do
      @checker.options['mode'] = 'write'
      @checker.options['filename'] = 'file.txt'
      @checker.options['data'] = '{{ data }}'
    end

    it "writes the data at data into a file" do
      client_mock = mock()
      mock(client_mock).put_object(bucket: @checker.options['bucket'], key: @checker.options['filename'], body: 'hello world!')
      mock(@checker).client { client_mock }
      event = Event.new(payload: {'data' => 'hello world!'})
      @checker.receive([event])
    end

    it "does nothing when mode is set to 'read'" do
      @checker.options['mode'] = 'read'
      event = Event.new(payload: {'data' => 'hello world!'})
      @checker.receive([event])
    end
  end
end
