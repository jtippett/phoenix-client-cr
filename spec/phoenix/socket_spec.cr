require "../spec_helper"

describe Phoenix::Socket do
  describe "#connect / #disconnect" do
    it "connects to a WebSocket endpoint" do
      server = TestServer.new
      server.start
      begin
        socket = Phoenix::Socket.new(endpoint: server.ws_url)
        socket.connected?.should be_false

        socket.connect
        sleep 50.milliseconds
        socket.connected?.should be_true

        socket.disconnect
        sleep 50.milliseconds
        socket.connected?.should be_false
      ensure
        socket.try &.disconnect
        server.stop
      end
    end
  end

  describe "#on_open / #on_close" do
    it "fires open callback on connect" do
      server = TestServer.new
      server.start
      begin
        socket = Phoenix::Socket.new(endpoint: server.ws_url)
        opened = false
        socket.on_open { opened = true }

        socket.connect
        sleep 50.milliseconds
        opened.should be_true
      ensure
        socket.try &.disconnect
        server.stop
      end
    end
  end

  describe "#channel" do
    it "creates a channel for a topic" do
      socket = Phoenix::Socket.new(endpoint: "ws://localhost:4000/socket/websocket")
      channel = socket.channel("room:lobby", {"user_id" => JSON::Any.new(1_i64)})
      channel.topic.should eq("room:lobby")
    end
  end

  describe "#make_ref" do
    it "returns incrementing string refs" do
      socket = Phoenix::Socket.new(endpoint: "ws://localhost:4000/socket/websocket")
      socket.make_ref.should eq("1")
      socket.make_ref.should eq("2")
      socket.make_ref.should eq("3")
    end
  end

  describe "params" do
    it "appends params to the URL as query params" do
      server = TestServer.new
      server.start
      begin
        socket = Phoenix::Socket.new(
          endpoint: server.ws_url,
          params: {"token" => "abc", "vsn" => "2.0.0"},
        )
        socket.connect
        sleep 50.milliseconds
        socket.connected?.should be_true
      ensure
        socket.try &.disconnect
        server.stop
      end
    end
  end

  describe "heartbeat" do
    it "sends heartbeat messages on interval" do
      server = TestServer.new
      server.start do |ws, msg|
        # Echo back heartbeat reply
        parsed = JSON.parse(msg)
        ref = parsed[1].as_s?
        reply = [nil, ref, "phoenix", "phx_reply", {"status" => "ok", "response" => {} of String => String}]
        ws.send(reply.to_json)
      end
      begin
        socket = Phoenix::Socket.new(
          endpoint: server.ws_url,
          heartbeat_interval: 50.milliseconds,
        )
        socket.connect
        sleep 200.milliseconds

        heartbeats = server.received_messages.select { |m|
          JSON.parse(m)[3].as_s == "heartbeat"
        }
        heartbeats.size.should be >= 2
      ensure
        socket.try &.disconnect
        server.stop
      end
    end
  end
end
