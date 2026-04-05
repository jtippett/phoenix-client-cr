require "../spec_helper"

describe "Socket + Channel integration" do
  it "joins a channel and receives reply" do
    server = TestServer.new
    server.start do |ws, msg|
      parsed = JSON.parse(msg)
      join_ref = parsed[0].as_s?
      ref = parsed[1].as_s?
      topic = parsed[2].as_s
      event = parsed[3].as_s

      if event == "phx_join"
        reply = [join_ref, ref, topic, "phx_reply", {"status" => "ok", "response" => {} of String => String}]
        ws.send(reply.to_json)
      end
    end

    begin
      socket = Phoenix::Socket.new(
        endpoint: server.ws_url,
        heartbeat_interval: 30.seconds,
      )
      socket.connect
      sleep 50.milliseconds

      joined = false
      channel = socket.channel("room:test")
      channel.join.receive("ok") { |_| joined = true }

      sleep 100.milliseconds
      joined.should be_true
      channel.joined?.should be_true
    ensure
      socket.try &.disconnect
      server.stop
    end
  end

  it "pushes messages and receives replies" do
    server = TestServer.new
    server.start do |ws, msg|
      parsed = JSON.parse(msg)
      join_ref = parsed[0].as_s?
      ref = parsed[1].as_s?
      topic = parsed[2].as_s
      event = parsed[3].as_s

      if event == "phx_join"
        reply = [join_ref, ref, topic, "phx_reply", {"status" => "ok", "response" => {} of String => String}]
        ws.send(reply.to_json)
      elsif event == "new_msg"
        reply = [join_ref, ref, topic, "phx_reply", {"status" => "ok", "response" => {"id" => 1}}]
        ws.send(reply.to_json)
      end
    end

    begin
      socket = Phoenix::Socket.new(
        endpoint: server.ws_url,
        heartbeat_interval: 30.seconds,
      )
      socket.connect
      sleep 50.milliseconds

      channel = socket.channel("room:test")
      channel.join
      sleep 100.milliseconds

      reply_received = false
      channel.push("new_msg", JSON.parse(%({"body": "hello"}))).receive("ok") { |resp|
        reply_received = true
      }

      sleep 100.milliseconds
      reply_received.should be_true
    ensure
      socket.try &.disconnect
      server.stop
    end
  end

  it "fires push timeout when server does not reply" do
    server = TestServer.new
    # Server handles join but ignores all other messages (no reply)
    server.start do |ws, msg|
      parsed = JSON.parse(msg)
      event = parsed[3].as_s

      if event == "phx_join"
        join_ref = parsed[0].as_s?
        ref = parsed[1].as_s?
        topic = parsed[2].as_s
        reply = [join_ref, ref, topic, "phx_reply", {"status" => "ok", "response" => {} of String => String}]
        ws.send(reply.to_json)
      end
      # All other events are intentionally ignored — no reply sent
    end

    begin
      socket = Phoenix::Socket.new(
        endpoint: server.ws_url,
        heartbeat_interval: 30.seconds,
      )
      socket.connect
      sleep 50.milliseconds

      channel = socket.channel("room:test")
      channel.join
      sleep 100.milliseconds
      channel.joined?.should be_true

      timed_out = false
      channel.push("no_reply_event", JSON.parse(%({"body": "hello"})), timeout: 100.milliseconds)
        .receive("timeout") { |_| timed_out = true }

      sleep 200.milliseconds
      timed_out.should be_true
    ensure
      socket.try &.disconnect
      server.stop
    end
  end

  it "auto-rejoins channels after socket reconnect" do
    join_handler = ->(ws : HTTP::WebSocket, msg : String) {
      parsed = JSON.parse(msg)
      join_ref = parsed[0].as_s?
      ref = parsed[1].as_s?
      topic = parsed[2].as_s
      event = parsed[3].as_s

      if event == "phx_join"
        reply = [join_ref, ref, topic, "phx_reply", {"status" => "ok", "response" => {} of String => String}]
        ws.send(reply.to_json)
      end
    }

    server = TestServer.new
    server.start(&join_handler)
    port = server.port

    begin
      socket = Phoenix::Socket.new(
        endpoint: server.ws_url,
        heartbeat_interval: 30.seconds,
        reconnect_after: ->(tries : Int32) : Time::Span { 50.milliseconds },
      )
      socket.connect
      sleep 50.milliseconds

      channel = socket.channel("room:test")
      channel.join
      sleep 100.milliseconds
      channel.joined?.should be_true

      # Stop server to simulate disconnect
      server.stop
      sleep 100.milliseconds

      # Channel should be in Errored state after disconnect
      channel.state.should eq(Phoenix::Channel::State::Errored)

      # Start a new server on the same port so the reconnect succeeds
      server2 = TestServer.new(port)
      server2.start(&join_handler)

      # Wait for reconnect + rejoin (reconnect_after is 50ms)
      sleep 500.milliseconds

      channel.joined?.should be_true
    ensure
      socket.try &.disconnect
      server.stop
      server2.try &.stop
    end
  end

  it "receives broadcast events" do
    server = TestServer.new
    server.start do |ws, msg|
      parsed = JSON.parse(msg)
      event = parsed[3].as_s

      if event == "phx_join"
        join_ref = parsed[0].as_s?
        ref = parsed[1].as_s?
        topic = parsed[2].as_s
        reply = [join_ref, ref, topic, "phx_reply", {"status" => "ok", "response" => {} of String => String}]
        ws.send(reply.to_json)

        # Send a broadcast after join
        spawn do
          sleep 20.milliseconds
          broadcast = [nil, nil, topic, "new_msg", {"body" => "from server"}]
          ws.send(broadcast.to_json)
        end
      end
    end

    begin
      socket = Phoenix::Socket.new(
        endpoint: server.ws_url,
        heartbeat_interval: 30.seconds,
      )
      socket.connect
      sleep 50.milliseconds

      channel = socket.channel("room:test")
      received_body = nil
      channel.on("new_msg") { |payload| received_body = payload["body"].as_s }
      channel.join
      sleep 200.milliseconds

      received_body.should eq("from server")
    ensure
      socket.try &.disconnect
      server.stop
    end
  end
end
