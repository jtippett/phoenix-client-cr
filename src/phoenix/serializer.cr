module Phoenix
  abstract class Serializer
    abstract def encode(msg : Message) : String | Bytes
    abstract def decode_text(raw : String) : Message
    abstract def decode_binary(raw : Bytes) : Message
  end

  class Serializer::JSON < Serializer
    def encode(msg : Message) : String | Bytes
      String.build do |str|
        builder = ::JSON::Builder.new(str)
        builder.document do
          builder.array do
            if jr = msg.join_ref
              builder.string(jr)
            else
              builder.null
            end
            if r = msg.ref
              builder.string(r)
            else
              builder.null
            end
            builder.string(msg.topic)
            builder.string(msg.event)
            builder.raw(msg.payload.to_json)
          end
        end
      end
    end

    def decode_text(raw : String) : Message
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
      # JSON serializer doesn't handle binary frames
      # Fall back to treating as UTF-8 text
      decode_text(String.new(raw))
    end
  end
end

require "./serializer/binary"
