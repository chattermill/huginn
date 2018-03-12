require 'rails_helper'

describe "Sidekiq unique jobs" do

  class Agents::TestAgent < Agent
    default_schedule "never"

    def check
      create_event payload: {message: 'Hello World'}
    end
  end

  class Agents::FakeAgent < Agent
    default_schedule "never"

    def check
      create_event payload: {message: 'Hello again'}
    end
  end

  before do
    Sidekiq::Queues.clear_all
    Sidekiq.redis(&:flushdb)

    stub(Agents::TestAgent).valid_type?("Agents::TestAgent") { true }

    @agent = Agents::TestAgent.new(:name => "some agent")
    @agent.user = users(:bob)
    @agent.save!
  end

  describe 'AgentCheckJobs' do

    it "doesn't enqueue AgentCheckJobs for same agent" do
      Sidekiq::Testing.disable! do
        expect(Sidekiq::Queue.new("default").size).to eq(0)

        AgentCheckJob.perform_later(@agent.id)
        AgentCheckJob.perform_later(@agent.id)

        expect(Sidekiq::Queue.new("default").size).to eq(1)

        Sidekiq::Queue.new("default").each do |job|
          expect(job.args.first["job_class"]).to eq("AgentCheckJob")
          expect(job.args.first["arguments"]).to eq([@agent.id])
        end
      end
    end

    it "enqueue AgentCheckJobs for each diferent agents" do
      stub(Agents::FakeAgent).valid_type?("Agents::FakeAgent") { true }

      @fake_agent = Agents::FakeAgent.new(:name => "another agent")
      @fake_agent.user = users(:bob)
      @fake_agent.save!

      Sidekiq::Testing.disable! do
        expect(Sidekiq::Queue.new("default").size).to eq(0)

        AgentCheckJob.perform_later(@agent.id)
        AgentCheckJob.perform_later(@fake_agent.id)

        job_class = Sidekiq::Queue.new("default").map{ |j| j.args.first["job_class"] }.uniq
        args = Sidekiq::Queue.new("default").map{ |j| j.args.first["arguments"] }.flatten.sort

        expect(Sidekiq::Queue.new("default").size).to eq(2)
        expect(job_class).to eq(["AgentCheckJob"])
        expect(args).to eq([@agent.id, @fake_agent.id])
      end
    end
  end

  describe 'AgentReceiveJob' do
    it "enqueue jobs for same arguments" do
      event = @agent.create_event payload: {message: 'Hello again'}

      Sidekiq::Testing.disable! do
        expect(Sidekiq::Queue.new("default").size).to eq(0)

        AgentReceiveJob.perform_later(@agent.id, [event.id])
        AgentReceiveJob.perform_later(@agent.id, [event.id])

        job_class = Sidekiq::Queue.new("default").map{ |j| j.args.first["job_class"] }.uniq
        args = Sidekiq::Queue.new("default").map{ |j| j.args.first["arguments"] }.uniq

        expect(Sidekiq::Queue.new("default").size).to eq(2)
        expect(job_class).to eq(["AgentReceiveJob"])
        expect(args.first).to eq([@agent.id, [event.id]])
      end
    end
  end

  describe 'AgentPropagateJob' do
    it "enqueue jobs for same arguments" do
      Sidekiq::Testing.disable! do
        expect(Sidekiq::Queue.new("propagation").size).to eq(0)

        AgentPropagateJob.perform_later
        AgentPropagateJob.perform_later

        job_class = Sidekiq::Queue.new("propagation").map{ |j| j.args.first["job_class"] }.uniq

        expect(Sidekiq::Queue.new("propagation").size).to eq(2)
        expect(job_class).to eq(["AgentPropagateJob"])
      end
    end
  end

  describe 'AgentRunScheduleJob' do
    it "enqueue jobs for same arguments" do
      Sidekiq::Testing.disable! do
        expect(Sidekiq::Queue.new("default").size).to eq(0)

        AgentRunScheduleJob.perform_later('every_1m')
        AgentRunScheduleJob.perform_later('every_1m')

        job_class = Sidekiq::Queue.new("default").map{ |j| j.args.first["job_class"] }.uniq

        expect(Sidekiq::Queue.new("default").size).to eq(2)
        expect(job_class).to eq(["AgentRunScheduleJob"])
      end
    end
  end

end
