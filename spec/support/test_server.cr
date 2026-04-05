require "http/server"
require "http/web_socket"

class TestServer
  getter port : Int32 = 0
  getter received_messages = [] of String
  @server : HTTP::Server? = nil
  @connections = [] of HTTP::WebSocket
  @bind_port : Int32

  def initialize(@bind_port : Int32 = 0)
  end

  def start(&on_message : HTTP::WebSocket, String ->) : Nil
    handler = HTTP::WebSocketHandler.new do |ws, ctx|
      @connections << ws
      ws.on_message do |msg|
        @received_messages << msg
        on_message.call(ws, msg)
      end
    end
    @server = server = HTTP::Server.new(handler)
    addr = server.bind_tcp("127.0.0.1", @bind_port, reuse_port: true)
    @port = addr.port
    spawn { server.listen }
    Fiber.yield # let server start
  end

  # Overload with no block
  def start : Nil
    start { |_ws, _msg| }
  end

  def send_to_all(msg : String) : Nil
    @connections.each &.send(msg)
  end

  def stop : Nil
    @connections.each { |ws| ws.close rescue nil }
    @server.try do |s|
      s.close rescue nil
    end
  end

  def ws_url(path = "/socket/websocket") : String
    "ws://127.0.0.1:#{@port}#{path}"
  end
end
