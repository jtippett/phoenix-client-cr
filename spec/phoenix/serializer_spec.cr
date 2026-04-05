require "../spec_helper"

describe Phoenix::Serializer::JSON do
  serializer = Phoenix::Serializer::JSON.new

  describe "#encode" do
    it "encodes a message as a JSON array" do
      msg = Phoenix::Message.new(
        join_ref: "1",
        ref: "2",
        topic: "room:lobby",
        event: "phx_join",
        payload: JSON.parse(%({"user": "alice"})),
      )

      result = serializer.encode(msg)
      result.should be_a(String)
      parsed = JSON.parse(result.as(String))
      parsed[0].as_s?.should eq("1")
      parsed[1].as_s?.should eq("2")
      parsed[2].as_s.should eq("room:lobby")
      parsed[3].as_s.should eq("phx_join")
      parsed[4]["user"].as_s.should eq("alice")
    end

    it "encodes nil refs as JSON null" do
      msg = Phoenix::Message.new(
        topic: "room:lobby",
        event: "broadcast",
        payload: JSON.parse("{}"),
      )

      result = serializer.encode(msg)
      parsed = JSON.parse(result.as(String))
      parsed[0].raw.should be_nil
      parsed[1].raw.should be_nil
    end
  end

  describe "#decode_text" do
    it "decodes a JSON array into a Message" do
      raw = %([\"1\",\"2\",\"room:lobby\",\"phx_reply\",{\"status\":\"ok\"}])
      msg = serializer.decode_text(raw)

      msg.join_ref.should eq("1")
      msg.ref.should eq("2")
      msg.topic.should eq("room:lobby")
      msg.event.should eq("phx_reply")
      msg.payload["status"].as_s.should eq("ok")
    end

    it "handles null refs" do
      raw = %([null,null,\"room:lobby\",\"broadcast\",{}])
      msg = serializer.decode_text(raw)

      msg.join_ref.should be_nil
      msg.ref.should be_nil
    end
  end
end
