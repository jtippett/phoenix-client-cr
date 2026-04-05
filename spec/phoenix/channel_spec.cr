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

  describe "#rejoin" do
    it "re-sends phx_join and transitions to Joining from Errored state" do
      socket = Phoenix::Socket.new("ws://localhost:4000/socket")
      ch = socket.channel("room:lobby")
      ch.join
      ch.trigger_join_reply(JSON.parse(%({"status": "ok", "response": {}})))
      ch.state.should eq(Phoenix::Channel::State::Joined)

      # Simulate error (e.g. socket disconnect)
      ch.trigger_error("connection closed")
      ch.state.should eq(Phoenix::Channel::State::Errored)

      # Rejoin should transition to Joining
      ch.rejoin
      ch.state.should eq(Phoenix::Channel::State::Joining)
    end

    it "re-sends phx_join and transitions to Joining from Joined state" do
      socket = Phoenix::Socket.new("ws://localhost:4000/socket")
      ch = socket.channel("room:lobby")
      ch.join
      ch.trigger_join_reply(JSON.parse(%({"status": "ok", "response": {}})))
      ch.state.should eq(Phoenix::Channel::State::Joined)

      ch.rejoin
      ch.state.should eq(Phoenix::Channel::State::Joining)
    end

    it "does nothing when state is Closed" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))
      ch.state.should eq(Phoenix::Channel::State::Closed)

      ch.rejoin
      ch.state.should eq(Phoenix::Channel::State::Closed)
    end

    it "does nothing when state is Leaving" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))
      ch.join
      ch.trigger_join_reply(JSON.parse(%({"status": "ok", "response": {}})))
      ch.leave
      ch.state.should eq(Phoenix::Channel::State::Leaving)

      ch.rejoin
      ch.state.should eq(Phoenix::Channel::State::Leaving)
    end

    it "transitions back to Joined after successful rejoin reply" do
      socket = Phoenix::Socket.new("ws://localhost:4000/socket")
      ch = socket.channel("room:lobby")
      ch.join
      ch.trigger_join_reply(JSON.parse(%({"status": "ok", "response": {}})))

      ch.trigger_error("connection closed")
      ch.state.should eq(Phoenix::Channel::State::Errored)

      ch.rejoin
      ch.state.should eq(Phoenix::Channel::State::Joining)

      # Simulate successful rejoin reply
      ch.trigger_join_reply(JSON.parse(%({"status": "ok", "response": {}})))
      ch.state.should eq(Phoenix::Channel::State::Joined)
    end
  end

  describe "ClosedError" do
    it "raises when pushing to a channel whose socket is disconnected" do
      # Create a socket and channel, join, then disconnect the socket
      socket = Phoenix::Socket.new("ws://localhost:4000/socket")
      ch = socket.channel("room:lobby")
      ch.join

      # Simulate successful join so channel reaches Joined state
      ch.trigger_join_reply(JSON.parse(%({"status": "ok", "response": {}})))
      ch.state.should eq(Phoenix::Channel::State::Joined)

      # Socket was never actually connected (@ws is nil), so connected? is false.
      # Pushing should raise ClosedError.
      socket.connected?.should be_false
      expect_raises(Phoenix::ClosedError, "Cannot push to closed socket") do
        ch.push("msg", JSON.parse(%({"body": "hello"})))
      end
    end

    it "raises when pushing to a channel with no socket" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))
      ch.join

      # Simulate successful join
      ch.trigger_join_reply(JSON.parse(%({"status": "ok", "response": {}})))
      ch.state.should eq(Phoenix::Channel::State::Joined)

      # Socket is nil, pushing should raise ClosedError
      expect_raises(Phoenix::ClosedError) do
        ch.push("msg", JSON.parse(%({"body": "hello"})))
      end
    end

    it "buffers pushes when channel is not yet joined (no raise)" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))
      ch.join
      ch.state.should eq(Phoenix::Channel::State::Joining)

      # Should not raise — pushes are buffered in non-Joined states
      push = ch.push("msg", JSON.parse(%({"body": "buffered"})))
      push.should be_a(Phoenix::Push)
    end
  end
end
