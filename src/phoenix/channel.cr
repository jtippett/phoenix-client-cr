module Phoenix
  class Channel
    enum State
      Closed
      Joining
      Joined
      Leaving
      Errored
    end

    getter topic : String
    getter state : State = State::Closed
    getter join_ref : String? = nil
    property socket : Socket? = nil

    @params : JSON::Any
    @bindings = [] of Binding
    @push_buffer = [] of Push
    @join_push : Push? = nil
    @joined_once = false
    @binding_ref = 0
    @timeout : Time::Span
    @rejoin_timer : Timer? = nil
    @pending_pushes = {} of String => Push

    private record Binding, event : String, ref : Int32, callback : Proc(JSON::Any, Nil)

    def initialize(
      @topic : String,
      @params : JSON::Any,
      @timeout : Time::Span = 10.seconds,
      @rejoin_after : Proc(Int32, Time::Span) = Timer::DEFAULT_BACKOFF,
    )
    end

    def join(timeout : Time::Span = @timeout) : Push
      raise AlreadyJoinedError.new(@topic) if @joined_once
      @joined_once = true
      @state = State::Joining

      @join_push = push = Push.new(
        event: Message::CHANNEL_EVENTS[:join],
        payload: @params,
        timeout: timeout,
      )

      push.receive("ok") do |_resp|
        @state = State::Joined
        flush_push_buffer
      end

      push.receive("error") do |_resp|
        @state = State::Errored
      end

      push.receive("timeout") do |_|
        @state = State::Errored
      end

      send_push(push)
      push
    end

    def leave(timeout : Time::Span = @timeout) : Push
      @state = State::Leaving

      push = Push.new(
        event: Message::CHANNEL_EVENTS[:leave],
        payload: JSON::Any.new({} of String => JSON::Any),
        timeout: timeout,
      )

      push.receive("ok") do |_|
        @state = State::Closed
      end

      push.receive("timeout") do |_|
        @state = State::Closed
      end

      send_push(push)
      push
    end

    def push(event : String, payload : JSON::Any, timeout : Time::Span = @timeout) : Push
      push = Push.new(event: event, payload: payload, timeout: timeout)
      if @state == State::Joined
        sock = @socket
        raise ClosedError.new unless sock && sock.connected?
        send_push(push)
      else
        @push_buffer << push
      end
      push
    end

    # Untyped event subscription
    def on(event : String, &callback : JSON::Any ->) : Int32
      @binding_ref += 1
      ref = @binding_ref
      @bindings << Binding.new(event: event, ref: ref, callback: callback)
      ref
    end

    # Typed event subscription
    def on(event : String, type : T.class, &callback : T ->) : Int32 forall T
      on(event) do |payload|
        callback.call(T.from_json(payload.to_json))
      end
    end

    def off(event : String, ref : Int32? = nil) : Nil
      if ref
        @bindings.reject! { |b| b.event == event && b.ref == ref }
      else
        @bindings.reject! { |b| b.event == event }
      end
    end

    def on_close(&callback : ->) : Int32
      on(Message::CHANNEL_EVENTS[:close]) { |_| callback.call }
    end

    def on_error(&callback : String ->) : Int32
      on(Message::CHANNEL_EVENTS[:error]) { |payload|
        reason = payload["reason"]?.try(&.as_s?) || "unknown"
        callback.call(reason)
      }
    end

    def joined? : Bool
      @state == State::Joined
    end

    # Called by Socket when a message arrives for this channel's topic
    def trigger(event : String, payload : JSON::Any, ref : String? = nil) : Nil
      @bindings.each do |binding|
        binding.callback.call(payload) if binding.event == event
      end
    end

    # Called by tests (and internally) to simulate join reply
    def trigger_join_reply(payload : JSON::Any) : Nil
      status = payload["status"]?.try(&.as_s?) || "error"
      response = payload["response"]? || JSON::Any.new({} of String => JSON::Any)
      @join_push.try &.trigger(status, response)
    end

    # Transition to errored state and fire phx_error bindings
    def trigger_error(reason : String) : Nil
      @state = State::Errored
      trigger(Message::CHANNEL_EVENTS[:error], JSON.parse(%({"reason": "#{reason}"})))
    end

    # Called by Socket after reconnecting to re-join channels that were
    # previously joined or errored.  Does nothing if the user explicitly
    # left or never joined.
    def rejoin : Nil
      return if @state.closed? || @state.leaving?

      if push = @join_push
        push.reset
        @state = State::Joining
        send_push(push)
      end
    end

    # Main message dispatcher called by Socket
    def handle_message(msg : Message) : Nil
      if msg.reply_event?
        if msg.ref == @join_push.try(&.ref)
          trigger_join_reply(msg.payload)
        elsif ref = msg.ref
          # Route reply to the pending push that sent it
          if push = @pending_pushes.delete(ref)
            status = msg.payload["status"]?.try(&.as_s?) || "error"
            response = msg.payload["response"]? || JSON::Any.new({} of String => JSON::Any)
            push.trigger(status, response)
          end
        end
      else
        trigger(msg.event, msg.payload, msg.ref)
      end
    end

    private def send_push(push : Push) : Nil
      if sock = @socket
        ref = sock.make_ref
        push.ref = ref

        # Track join_ref for the channel
        if push.event == Message::CHANNEL_EVENTS[:join]
          @join_ref = ref
        end

        # Track the push so we can route replies back to it
        @pending_pushes[ref] = push

        msg = Message.new(
          topic: @topic,
          event: push.event,
          payload: push.payload,
          ref: ref,
          join_ref: @join_ref,
        )
        sock.push(msg)

        # Schedule timeout so that push.receive("timeout") callbacks fire
        # if the server never replies within the push's timeout window.
        spawn do
          sleep push.timeout
          push.trigger_timeout
        end
      end
    end

    private def flush_push_buffer : Nil
      @push_buffer.each { |push| send_push(push) }
      @push_buffer.clear
    end
  end
end
