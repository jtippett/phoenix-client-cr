require "../spec_helper"

struct TestPayload
  include JSON::Serializable
  getter body : String
end

describe Phoenix::Channel do
  describe "#new" do
    it "initializes with topic and params" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse(%({"user": "alice"})))
      ch.topic.should eq("room:lobby")
      ch.state.should eq(Phoenix::Channel::State::Closed)
    end
  end

  describe "#join" do
    it "returns a Push" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))
      push = ch.join
      push.should be_a(Phoenix::Push)
      push.event.should eq("phx_join")
    end

    it "transitions to Joining state" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))
      ch.join
      ch.state.should eq(Phoenix::Channel::State::Joining)
    end

    it "raises on double join" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))
      ch.join
      expect_raises(Phoenix::AlreadyJoinedError) { ch.join }
    end
  end

  describe "#on / #off" do
    it "registers and fires event callbacks" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))

      received = nil
      ch.on("new_msg") { |payload| received = payload }

      payload = JSON.parse(%({"body": "hi"}))
      ch.trigger("new_msg", payload)

      received.should_not be_nil
      received.try &.["body"].as_s.should eq("hi")
    end

    it "returns a ref for unsubscribing" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))

      count = 0
      ref = ch.on("msg") { |_| count += 1 }

      ch.trigger("msg", JSON.parse("{}"))
      count.should eq(1)

      ch.off("msg", ref)
      ch.trigger("msg", JSON.parse("{}"))
      count.should eq(1)
    end

    it "removes all handlers when no ref given" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))

      count = 0
      ch.on("msg") { |_| count += 1 }
      ch.on("msg") { |_| count += 1 }

      ch.trigger("msg", JSON.parse("{}"))
      count.should eq(2)

      ch.off("msg")
      ch.trigger("msg", JSON.parse("{}"))
      count.should eq(2)
    end
  end

  describe "#on (typed)" do
    it "deserializes payload to the given type" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))

      received = nil
      ch.on("msg", TestPayload) { |msg| received = msg }

      ch.trigger("msg", JSON.parse(%({"body": "typed hello"})))
      received.should_not be_nil
      received.try &.body.should eq("typed hello")
    end
  end

  describe "#push" do
    it "returns a Push" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))
      push = ch.push("msg", JSON.parse(%({"body": "hi"})))
      push.should be_a(Phoenix::Push)
      push.event.should eq("msg")
    end
  end

  describe "#leave" do
    it "transitions to Leaving state" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))
      ch.join
      # Simulate join success
      ch.trigger_join_reply(JSON.parse(%({"status": "ok", "response": {}})))
      ch.state.should eq(Phoenix::Channel::State::Joined)

      ch.leave
      ch.state.should eq(Phoenix::Channel::State::Leaving)
    end
  end

  describe "#joined?" do
    it "returns true only when Joined" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))
      ch.joined?.should be_false

      ch.join
      ch.joined?.should be_false # still Joining

      ch.trigger_join_reply(JSON.parse(%({"status": "ok", "response": {}})))
      ch.joined?.should be_true
    end
  end

  describe "#trigger_join_reply" do
    it "transitions to Joined on ok status" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))
      ch.join
      ch.state.should eq(Phoenix::Channel::State::Joining)

      ch.trigger_join_reply(JSON.parse(%({"status": "ok", "response": {}})))
      ch.state.should eq(Phoenix::Channel::State::Joined)
    end
  end
end
