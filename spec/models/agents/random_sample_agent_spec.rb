require 'rails_helper'

describe Agents::RandomSampleAgent do
  let(:agent) do
    _agent = Agents::RandomSampleAgent.new(name: 'My RandomSampleAgent')
    _agent.options = _agent.default_options.merge('percent' => 30)
    _agent.user = users(:bob)
    _agent.sources << agents(:bob_website_agent)
    _agent.save!
    _agent
  end

  def create_event
    _event = Event.new(payload: { random: rand })
    _event.agent = agents(:bob_website_agent)
    _event.save!
    _event
  end

  let(:first_event) { create_event }
  let(:second_event) { create_event }
  let(:third_event) { create_event }

  describe "#working?" do
    it "checks if events have been received within expected receive period" do
      expect(agent).not_to be_working
      Agents::RandomSampleAgent.async_receive agent.id, [events(:bob_website_agent_event).id]
      expect(agent.reload).to be_working
      the_future = (agent.options[:expected_receive_period_in_days].to_i + 1).days.from_now
      stub(Time).now { the_future }
      expect(agent.reload).not_to be_working
    end
  end

  describe "validation" do
    before do
      expect(agent).to be_valid
    end

    it "should validate percent" do
      agent.options.delete('percent')
      expect(agent).not_to be_valid
      agent.options['percent'] = ""
      expect(agent).not_to be_valid
      agent.options['percent'] = "0"
      expect(agent).not_to be_valid
      agent.options['percent'] = "101"
      expect(agent).not_to be_valid
      agent.options['percent'] = "10"
      expect(agent).to be_valid
    end

    it "should validate presence of expected_receive_period_in_days" do
      agent.options['expected_receive_period_in_days'] = ""
      expect(agent).not_to be_valid
      agent.options['expected_receive_period_in_days'] = 0
      expect(agent).not_to be_valid
      agent.options['expected_receive_period_in_days'] = -1
      expect(agent).not_to be_valid
    end
  end

  describe "#receive" do
    it "emits a random sample of events accordingly to percent option" do
      agent.receive([first_event])
      expect(agent.events.count).to eq 0
      agent.receive([first_event, second_event, third_event])
      expect(agent.events.count).to eq 1
    end
  end
end
