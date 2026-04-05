module Phoenix
  class Serializer::Binary < Serializer
    # Message kinds
    PUSH      = 0u8
    REPLY     = 1u8
    BROADCAST = 2u8

    HEADER_LENGTH = 5

    def encode(msg : Message) : String | Bytes
      payload_bytes = msg.payload.to_json.to_slice
      join_ref_bytes = (msg.join_ref || "").to_slice
      ref_bytes = (msg.ref || "").to_slice
      topic_bytes = msg.topic.to_slice
      event_bytes = msg.event.to_slice

      io = IO::Memory.new(
        HEADER_LENGTH +
        join_ref_bytes.size +
        ref_bytes.size +
        topic_bytes.size +
        event_bytes.size +
        payload_bytes.size
      )

      io.write_byte(PUSH)
      io.write_byte(join_ref_bytes.size.to_u8)
      io.write_byte(ref_bytes.size.to_u8)
      io.write_byte(topic_bytes.size.to_u8)
      io.write_byte(event_bytes.size.to_u8)
      io.write(join_ref_bytes)
      io.write(ref_bytes)
      io.write(topic_bytes)
      io.write(event_bytes)
      io.write(payload_bytes)

      io.to_slice
    end

    def decode_text(raw : String) : Message
      # Binary serializer still receives text frames for some messages
      arr = ::JSON.parse(raw).as_a
      Message.new(
        join_ref: arr[0].as_s?,
        ref: arr[1].as_s?,
        topic: arr[2].as_s,
        event: arr[3].as_s,
        payload: arr[4],
      )
    end

    def decode_binary(raw : Bytes) : Message
      kind = raw[0]
      join_ref_len = raw[1].to_i
      ref_len = raw[2].to_i
      topic_len = raw[3].to_i
      event_len = raw[4].to_i

      offset = HEADER_LENGTH
      join_ref_str = String.new(raw[offset, join_ref_len])
      offset += join_ref_len

      ref_str = String.new(raw[offset, ref_len])
      offset += ref_len

      topic = String.new(raw[offset, topic_len])
      offset += topic_len

      event = String.new(raw[offset, event_len])
      offset += event_len

      payload_bytes = raw[offset..]
      payload = ::JSON.parse(String.new(payload_bytes))

      Message.new(
        join_ref: join_ref_len > 0 ? join_ref_str : nil,
        ref: ref_len > 0 ? ref_str : nil,
        topic: topic,
        event: event,
        payload: payload,
      )
    end
  end
end
