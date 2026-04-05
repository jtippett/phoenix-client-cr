require "../src/phoenix_client"

# Tracks user presence on a Phoenix channel.
#
# Usage:
#   crystal run examples/presence_tracker.cr
#
# Expects a Phoenix server at localhost:4000 with presence enabled on "room:lobby".

socket = Phoenix::Socket.new(
  endpoint: "ws://localhost:4000/socket/websocket",
  params: {"token" => "user-secret-token"},
)

socket.on_open { puts "Connected" }
socket.connect

channel = socket.channel("room:lobby")
presence = Phoenix::Presence.new(channel)

presence.on_join do |key, current, _new_presence|
  if current
    puts "#{key} opened another connection"
  else
    puts "#{key} is now online"
  end
end

presence.on_leave do |key, current, _left|
  metas = current["metas"]?.try(&.as_a?)
  if metas && metas.empty?
    puts "#{key} went offline"
  else
    puts "#{key} closed a connection"
  end
end

presence.on_sync do
  entries = presence.list
  puts "\n--- Online (#{entries.size}) ---"
  entries.each do |entry|
    devices = entry.metas.size
    puts "  #{entry.key} (#{devices} connection#{"s" if devices != 1})"
  end
  puts "---"
end

channel.join
  .receive("ok") { |_| puts "Joined, tracking presence..." }
  .receive("error") { |resp| abort "Failed to join: #{resp}" }

sleep
