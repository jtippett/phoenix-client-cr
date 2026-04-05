require "../spec_helper"

describe Phoenix::Message do
  describe ".new" do
    it "creates a message with all fields" do
      payload = JSON.parse(%({"text": "hello"}))
      msg = Phoenix::Message.new(
        join_ref: "1",
        ref: "2",
        topic: "room:lobby",
        event: "phx_reply",
        payload: payload,
      )

      msg.join_ref.should eq("1")
      msg.ref.should eq("2")
      msg.topic.should eq("room:lobby")
      msg.event.should eq("phx_reply")
      msg.payload["text"].as_s.should eq("hello")
    end

    it "allows nil join_ref and ref" do
      msg = Phoenix::Message.new(
        topic: "room:lobby",
        event: "broadcast",
        payload: JSON.parse("{}"),
      )

      msg.join_ref.should be_nil
      msg.ref.should be_nil
    end
  end

  describe "#reply_event?" do
    it "returns true for phx_reply" do
      msg = Phoenix::Message.new(topic: "t", event: "phx_reply", payload: JSON.parse("{}"))
      msg.reply_event?.should be_true
    end

    it "returns false for other events" do
      msg = Phoenix::Message.new(topic: "t", event: "custom", payload: JSON.parse("{}"))
      msg.reply_event?.should be_false
    end
  end
end
