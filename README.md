# phoenix_client

A Crystal client for [Phoenix Framework](https://phoenixframework.org/) channels and sockets. Connects to Phoenix servers over WebSocket using protocol v2, with support for channels, presence tracking, and both JSON and binary serialization.

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  phoenix_client:
    github: jtippett/phoenix-client-cr
```

Then run `shards install`.

## Quick Start

```crystal
require "phoenix_client"

socket = Phoenix::Socket.new(
  endpoint: "ws://localhost:4000/socket/websocket",
  params: {"token" => "user-secret"},
)

socket.on_open { puts "Connected!" }
socket.connect

channel = socket.channel("room:lobby")

channel.on("new_msg") do |payload|
  puts "#{payload["user"]}: #{payload["body"]}"
end

channel.join
  .receive("ok") { |_| puts "Joined lobby" }
  .receive("error") { |resp| puts "Join failed: #{resp}" }

sleep
```

## API Guide

### Socket

`Phoenix::Socket` manages the WebSocket connection, heartbeat, and automatic reconnection.

```crystal
socket = Phoenix::Socket.new(
  endpoint: "ws://localhost:4000/socket/websocket",
  params: {"token" => "secret"},          # query params sent on connect
  heartbeat_interval: 30.seconds,          # default
  timeout: 10.seconds,                     # default push/join timeout
  serializer: Phoenix::Serializer::JSON.new, # or Binary.new
  logger: Log.for("phoenix"),              # nil to disable
)

socket.connect
socket.disconnect
socket.connected? # => Bool
```

**Callbacks:**

```crystal
ref = socket.on_open { puts "connected" }
ref = socket.on_close { |code, reason| puts "closed: #{reason}" }
ref = socket.on_error { |ex| puts "error: #{ex.message}" }

# Remove a callback by ref
socket.off(ref)
```

**Dynamic params** for token refresh on reconnect:

```crystal
socket = Phoenix::Socket.new(
  endpoint: "ws://localhost:4000/socket/websocket",
  params: ->{ {"token" => fetch_fresh_token()} },
)
```

**Reconnection** happens automatically on unexpected disconnection with exponential backoff (1s, 2s, 5s, 10s). Calling `disconnect` explicitly stops reconnection attempts.

### Channel

Channels provide topic-based pub/sub over a socket connection.

```crystal
channel = socket.channel("room:lobby", {"user_id" => "42"})
```

**Joining and leaving:**

```crystal
channel.join
  .receive("ok") { |resp| puts "Joined: #{resp}" }
  .receive("error") { |resp| puts "Denied: #{resp}" }
  .receive("timeout") { |_| puts "Server unreachable" }

channel.leave
  .receive("ok") { |_| puts "Left channel" }
```

**Sending messages:**

```crystal
channel.push("new_msg", JSON.parse(%({"body": "Hello!"})))
  .receive("ok") { |resp| puts "Sent" }
  .receive("error") { |resp| puts "Failed: #{resp}" }
  .receive("timeout") { |_| puts "Timed out" }
```

**Receiving events:**

```crystal
# Subscribe
ref = channel.on("new_msg") { |payload| puts payload["body"] }

# Unsubscribe by ref
channel.off("new_msg", ref)

# Unsubscribe all handlers for an event
channel.off("new_msg")
```

**Lifecycle hooks:**

```crystal
channel.on_close { puts "Channel closed" }
channel.on_error { |reason| puts "Channel error: #{reason}" }
```

**State:**

```crystal
channel.joined?  # => Bool
channel.state    # => Phoenix::Channel::State (Closed, Joining, Joined, Leaving, Errored)
channel.topic    # => "room:lobby"
```

### Typed Payloads

For compile-time type safety, pass a `JSON::Serializable` type to `on`:

```crystal
struct ChatMessage
  include JSON::Serializable
  getter user : String
  getter body : String
end

channel.on("new_msg", ChatMessage) do |msg|
  puts "#{msg.user}: #{msg.body}"  # fully typed, no .as_s needed
end
```

### Presence

Track real-time user presence with automatic state synchronization.

```crystal
presence = Phoenix::Presence.new(channel)

presence.on_join do |key, _current, new_presence|
  puts "#{key} joined"
end

presence.on_leave do |key, _current, _left|
  puts "#{key} left"
end

presence.on_sync do
  users = presence.list
  puts "Online: #{users.map(&.key).join(", ")}"
end
```

**Listing presence:**

```crystal
# All entries
entries = presence.list  # => Array(Phoenix::Presence::Entry)
entries.each do |entry|
  puts "#{entry.key}: #{entry.metas.size} connections"
end

# With a transform
names = presence.list { |key, entry| key }
```

Presence automatically subscribes to `presence_state` and `presence_diff` events on the channel. The sync/diff algorithm handles full state reconciliation and incremental updates, including proper ordering of diffs that arrive during initial sync.

### Serializers

Two built-in serializers implement Phoenix protocol v2:

```crystal
# JSON (default) — human-readable, works with all Phoenix servers
socket = Phoenix::Socket.new(
  endpoint: url,
  serializer: Phoenix::Serializer::JSON.new,
)

# Binary — compact wire format for bandwidth-sensitive applications
socket = Phoenix::Socket.new(
  endpoint: url,
  serializer: Phoenix::Serializer::Binary.new,
)
```

**Custom serializers** can be created by subclassing `Phoenix::Serializer`:

```crystal
class MySerializer < Phoenix::Serializer
  def encode(msg : Phoenix::Message) : String | Bytes
    # your encoding logic
  end

  def decode_text(raw : String) : Phoenix::Message
    # decode text frames
  end

  def decode_binary(raw : Bytes) : Phoenix::Message
    # decode binary frames
  end
end
```

### Error Handling

Only programmer errors raise exceptions:

| Exception | Cause |
|---|---|
| `Phoenix::AlreadyJoinedError` | Calling `join` twice on the same channel |
| `Phoenix::ClosedError` | Pushing to a closed socket |

Network errors are handled automatically — the socket reconnects with exponential backoff, and channels rejoin on reconnection. Use callbacks to observe these events:

```crystal
socket.on_error { |ex| Log.warn { "Socket error: #{ex.message}" } }
channel.on_error { |reason| Log.warn { "Channel error: #{reason}" } }
```

### Logging

Pass a `Log` instance to enable protocol-level logging:

```crystal
socket = Phoenix::Socket.new(
  endpoint: url,
  logger: Log.for("phoenix"),
)
```

Log levels used:
- `debug` — message sent/received
- `info` — connect, disconnect, channel join/leave
- `warn` — heartbeat timeout, reconnecting
- `error` — WebSocket errors

## Examples

See the [`examples/`](examples/) directory:

- [`chat_client.cr`](examples/chat_client.cr) — minimal chat client
- [`presence_tracker.cr`](examples/presence_tracker.cr) — real-time presence tracking

## Development

Run tests:

```
crystal spec
```

Generate API docs:

```
crystal doc
```

## License

MIT
