require "../src/phoenix_client"

# A simple chat client that connects to a Phoenix chat server.
#
# Usage:
#   crystal run examples/chat_client.cr
#
# Expects a Phoenix server at localhost:4000 with a "room:lobby" channel.

socket = Phoenix::Socket.new(
  endpoint: "ws://localhost:4000/socket/websocket",
  params: {"token" => "user-secret-token"},
  logger: Log.for("phoenix"),
)

socket.on_open { puts "Connected to server" }
socket.on_close { |_code, reason| puts "Disconnected: #{reason}" }
socket.on_error { |ex| puts "Socket error: #{ex.message}" }

socket.connect

# Join a channel
channel = socket.channel("room:lobby", {"username" => "crystal_user"})

channel.on("new_msg") do |payload|
  user = payload["username"]?.try(&.as_s?) || "anonymous"
  body = payload["body"]?.try(&.as_s?) || ""
  puts "[#{user}] #{body}"
end

channel.join
  .receive("ok") { |_| puts "Joined lobby. Type a message and press Enter." }
  .receive("error") { |resp| abort "Failed to join: #{resp}" }
  .receive("timeout") { |_| abort "Join timed out" }

# Read from stdin and send messages
loop do
  if line = gets
    line = line.strip
    next if line.empty?

    channel.push("new_msg", JSON.parse({"body" => line}.to_json))
      .receive("ok") { |_| }
      .receive("error") { |resp| puts "Send failed: #{resp}" }
  else
    break
  end
end

socket.disconnect
