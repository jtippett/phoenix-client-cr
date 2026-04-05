module Phoenix
  struct Message
    getter join_ref : String?
    getter ref : String?
    getter topic : String
    getter event : String
    getter payload : JSON::Any

    def initialize(
      @topic : String,
      @event : String,
      @payload : JSON::Any,
      @join_ref : String? = nil,
      @ref : String? = nil,
    )
    end

    # Phoenix protocol events
    CHANNEL_EVENTS = {
      join:  "phx_join",
      leave: "phx_leave",
      reply: "phx_reply",
      error: "phx_error",
      close: "phx_close",
    }

    def reply_event? : Bool
      @event == CHANNEL_EVENTS[:reply]
    end
  end
end
