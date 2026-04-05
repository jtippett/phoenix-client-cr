require "http/web_socket"
require "uri"

module Phoenix
  class Socket
    Log = ::Log.for("phoenix")

    getter endpoint : String
    @ws : HTTP::WebSocket? = nil
    @channels = [] of Channel
    @ref : UInt64 = 0_u64
    @heartbeat_interval : Time::Span
    @heartbeat_ref : String? = nil
    @heartbeat_generation : Int32 = 0
    @timeout : Time::Span
    @serializer : Serializer
    @params : Hash(String, String) | Proc(Hash(String, String))
    @reconnect_timer : Timer
    @logger : ::Log?
    @explicitly_disconnected = false

    @callback_ref = 0

    private record CallbackEntry(T), ref : Int32, callback : T

    @open_entries = [] of CallbackEntry(Proc(Nil))
    @close_entries = [] of CallbackEntry(Proc(UInt16?, String?, Nil))
    @error_entries = [] of CallbackEntry(Proc(Exception, Nil))

    def initialize(
      @endpoint : String,
      params : Hash(String, String) | Proc(Hash(String, String)) = {} of String => String,
      @heartbeat_interval : Time::Span = 30.seconds,
      reconnect_after : Proc(Int32, Time::Span) = Timer::DEFAULT_BACKOFF,
      @timeout : Time::Span = 10.seconds,
      @serializer : Serializer = Serializer::JSON.new,
      @logger : ::Log? = nil,
    )
      @params = params
      @reconnect_timer = Timer.new(
        callback: -> { reconnect },
        timer_calc: reconnect_after,
      )
    end

    def connect : Nil
      return if @ws
      @explicitly_disconnected = false

      uri = build_uri
      @logger.try &.info { "connecting to #{uri}" }

      spawn do
        begin
          ws = HTTP::WebSocket.new(uri)
          @ws = ws

          ws.on_message { |msg| on_ws_message(msg) }
          ws.on_binary { |bytes| on_ws_binary(bytes) }
          ws.on_close { |code, reason| on_ws_close(code, reason) }

          @open_entries.each &.callback.call
          @reconnect_timer.reset
          trigger_channel_rejoins
          start_heartbeat

          ws.run
        rescue ex
          @logger.try &.error(exception: ex) { "WebSocket error" }
          @ws = nil
          @error_entries.each &.callback.call(ex)
          schedule_reconnect unless @explicitly_disconnected
        end
      end

      Fiber.yield
    end

    def disconnect(code : UInt16? = nil, reason : String? = nil) : Nil
      @explicitly_disconnected = true
      @reconnect_timer.reset
      stop_heartbeat
      @ws.try do |ws|
        @logger.try &.info { "disconnecting" }
        ws.close(code: HTTP::WebSocket::CloseCode::NormalClosure, message: reason || "disconnect") rescue nil
        @ws = nil
      end
    end

    def connected? : Bool
      !@ws.nil?
    end

    def channel(topic : String, params : JSON::Any = JSON::Any.new({} of String => JSON::Any)) : Channel
      ch = Channel.new(topic: topic, params: params, timeout: @timeout)
      ch.socket = self
      @channels << ch
      ch
    end

    # Overload for hash convenience
    def channel(topic : String, params : Hash) : Channel
      channel(topic, JSON.parse(params.to_json))
    end

    def make_ref : String
      @ref += 1
      @ref.to_s
    end

    def push(msg : Message) : Nil
      encoded = @serializer.encode(msg)
      case encoded
      when String then @ws.try &.send(encoded)
      when Bytes  then @ws.try &.send(encoded)
      end
    end

    def on_open(&callback : ->) : Int32
      ref = next_callback_ref
      @open_entries << CallbackEntry.new(ref: ref, callback: callback)
      ref
    end

    def on_close(&callback : UInt16?, String? ->) : Int32
      ref = next_callback_ref
      @close_entries << CallbackEntry.new(ref: ref, callback: callback)
      ref
    end

    def on_error(&callback : Exception ->) : Int32
      ref = next_callback_ref
      @error_entries << CallbackEntry.new(ref: ref, callback: callback)
      ref
    end

    def off(ref : Int32) : Nil
      @open_entries.reject! { |e| e.ref == ref }
      @close_entries.reject! { |e| e.ref == ref }
      @error_entries.reject! { |e| e.ref == ref }
    end

    # Called by Channel to remove itself
    def remove_channel(channel : Channel) : Nil
      @channels.reject! { |ch| ch == channel }
    end

    private def next_callback_ref : Int32
      @callback_ref += 1
    end

    private def build_uri : URI
      uri = URI.parse(@endpoint)
      current_params = case p = @params
                       when Hash then p
                       when Proc then p.call
                       else           {} of String => String
                       end

      query_parts = [] of String
      if existing = uri.query
        query_parts << existing
      end
      current_params.each { |k, v| query_parts << "#{URI.encode_www_form(k)}=#{URI.encode_www_form(v)}" }
      query_parts << "vsn=2.0.0"
      uri.query = query_parts.join("&")
      uri
    end

    private def on_ws_message(raw : String) : Nil
      msg = @serializer.decode_text(raw)
      @logger.try &.debug { "recv: #{msg.topic} #{msg.event}" }
      route_message(msg)
    end

    private def on_ws_binary(raw : Bytes) : Nil
      msg = @serializer.decode_binary(raw)
      @logger.try &.debug { "recv binary: #{msg.topic} #{msg.event}" }
      route_message(msg)
    end

    private def route_message(msg : Message) : Nil
      # Handle heartbeat reply
      if msg.topic == "phoenix" && msg.ref == @heartbeat_ref
        @heartbeat_ref = nil
        return
      end

      # Route to matching channels
      @channels.each do |channel|
        next unless channel.topic == msg.topic
        channel.handle_message(msg)
      end
    end

    private def on_ws_close(code, reason) : Nil
      @logger.try &.info { "connection closed: #{reason}" }
      @ws = nil
      stop_heartbeat
      @close_entries.each &.callback.call(code.try(&.to_u16), reason)
      @channels.each &.trigger_error("connection closed")
      schedule_reconnect unless @explicitly_disconnected
    end

    private def trigger_channel_rejoins : Nil
      @channels.each(&.rejoin)
    end

    private def schedule_reconnect : Nil
      @logger.try &.warn { "scheduling reconnect" }
      @reconnect_timer.schedule_timeout
    end

    private def reconnect : Nil
      return if connected? || @explicitly_disconnected
      @logger.try &.info { "reconnecting" }
      connect
    end

    private def start_heartbeat : Nil
      @heartbeat_generation += 1
      gen = @heartbeat_generation
      spawn do
        loop do
          sleep @heartbeat_interval
          break if gen != @heartbeat_generation || !connected?
          send_heartbeat
        end
      end
    end

    private def stop_heartbeat : Nil
      @heartbeat_generation += 1
    end

    private def send_heartbeat : Nil
      if @heartbeat_ref
        # Previous heartbeat not acknowledged — connection is dead
        @logger.try &.warn { "heartbeat timeout" }
        @heartbeat_ref = nil
        if ws = @ws
          ws.close(code: HTTP::WebSocket::CloseCode::NormalClosure, message: "heartbeat timeout") rescue nil
        end
        return
      end

      @heartbeat_ref = make_ref
      push(Message.new(
        topic: "phoenix",
        event: "heartbeat",
        payload: JSON::Any.new({} of String => JSON::Any),
        ref: @heartbeat_ref,
      ))
    end
  end
end
