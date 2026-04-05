require "../spec_helper"

describe Phoenix::Serializer::Binary do
  serializer = Phoenix::Serializer::Binary.new

  describe "#encode" do
    it "encodes a push message (kind 0) as binary" do
      msg = Phoenix::Message.new(
        join_ref: "1",
        ref: "2",
        topic: "room:lobby",
        event: "msg",
        payload: JSON.parse(%({"text": "hi"})),
      )

      result = serializer.encode(msg)
      result.should be_a(Bytes)
      bytes = result.as(Bytes)

      # Header: kind=0, join_ref_len=1, ref_len=1, topic_len=10, event_len=3
      bytes[0].should eq(0u8) # push kind
      bytes[1].should eq(1u8) # join_ref length
      bytes[2].should eq(1u8) # ref length
      bytes[3].should eq(10u8) # "room:lobby" length
      bytes[4].should eq(3u8) # "msg" length
    end
  end

  describe "#decode_binary" do
    it "decodes a reply message (kind 1)" do
      # Build a reply binary frame manually
      join_ref = "1"
      ref = "5"
      topic = "room:lobby"
      event = "phx_reply"
      payload = %({"status":"ok","response":{}})

      io = IO::Memory.new
      io.write_byte(1u8) # kind = reply
      io.write_byte(join_ref.bytesize.to_u8)
      io.write_byte(ref.bytesize.to_u8)
      io.write_byte(topic.bytesize.to_u8)
      io.write_byte(event.bytesize.to_u8)
      io << join_ref << ref << topic << event << payload

      msg = serializer.decode_binary(io.to_slice)

      msg.join_ref.should eq("1")
      msg.ref.should eq("5")
      msg.topic.should eq("room:lobby")
      msg.event.should eq("phx_reply")
      msg.payload["status"].as_s.should eq("ok")
    end

    it "decodes a broadcast message (kind 2) with no join_ref or ref" do
      topic = "room:lobby"
      event = "new_msg"
      payload = %({"body":"hello"})

      io = IO::Memory.new
      io.write_byte(2u8) # kind = broadcast
      io.write_byte(0u8) # no join_ref
      io.write_byte(0u8) # no ref
      io.write_byte(topic.bytesize.to_u8)
      io.write_byte(event.bytesize.to_u8)
      io << topic << event << payload

      msg = serializer.decode_binary(io.to_slice)

      msg.join_ref.should be_nil
      msg.ref.should be_nil
      msg.topic.should eq("room:lobby")
      msg.event.should eq("new_msg")
      msg.payload["body"].as_s.should eq("hello")
    end
  end

  describe "#decode_text" do
    it "falls back to JSON parsing for text frames" do
      raw = %([null,"3","phoenix","heartbeat",{}])
      msg = serializer.decode_text(raw)
      msg.topic.should eq("phoenix")
      msg.event.should eq("heartbeat")
    end
  end
end
