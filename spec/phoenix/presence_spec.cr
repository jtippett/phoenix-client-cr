require "../spec_helper"

describe Phoenix::Presence do
  describe ".sync_state" do
    it "detects joins from empty state" do
      new_state = JSON.parse(%({
        "user1": {"metas": [{"phx_ref": "abc", "status": "online"}]}
      }))

      joins = [] of String
      leaves = [] of String

      result = Phoenix::Presence.sync_state(
        JSON::Any.new({} of String => JSON::Any),
        new_state,
        on_join: ->(key : String, _cur : JSON::Any?, _new : JSON::Any) { joins << key; nil },
        on_leave: ->(key : String, _cur : JSON::Any, _left : JSON::Any) { leaves << key; nil },
      )

      joins.should eq(["user1"])
      leaves.should be_empty
      result["user1"].should_not be_nil
    end

    it "detects leaves from state" do
      current = JSON.parse(%({
        "user1": {"metas": [{"phx_ref": "abc"}]},
        "user2": {"metas": [{"phx_ref": "def"}]}
      }))

      new_state = JSON.parse(%({
        "user1": {"metas": [{"phx_ref": "abc"}]}
      }))

      leaves = [] of String
      Phoenix::Presence.sync_state(current, new_state,
        on_join: ->(_k : String, _c : JSON::Any?, _n : JSON::Any) { nil },
        on_leave: ->(key : String, _c : JSON::Any, _l : JSON::Any) { leaves << key; nil },
      )

      leaves.should eq(["user2"])
    end

    it "detects meta changes for existing users" do
      current = JSON.parse(%({
        "user1": {"metas": [{"phx_ref": "abc"}]}
      }))

      new_state = JSON.parse(%({
        "user1": {"metas": [{"phx_ref": "abc"}, {"phx_ref": "def"}]}
      }))

      joins = [] of String
      Phoenix::Presence.sync_state(current, new_state,
        on_join: ->(key : String, _c : JSON::Any?, _n : JSON::Any) { joins << key; nil },
        on_leave: ->(_k : String, _c : JSON::Any, _l : JSON::Any) { nil },
      )

      joins.should eq(["user1"])
    end
  end

  describe ".sync_diff" do
    it "applies joins" do
      state = JSON.parse(%({
        "user1": {"metas": [{"phx_ref": "abc"}]}
      }))

      diff = JSON.parse(%({
        "joins": {"user2": {"metas": [{"phx_ref": "def"}]}},
        "leaves": {}
      }))

      result = Phoenix::Presence.sync_diff(state, diff,
        on_join: ->(_k : String, _c : JSON::Any?, _n : JSON::Any) { nil },
        on_leave: ->(_k : String, _c : JSON::Any, _l : JSON::Any) { nil },
      )

      result["user1"].should_not be_nil
      result["user2"].should_not be_nil
    end

    it "applies leaves and removes empty entries" do
      state = JSON.parse(%({
        "user1": {"metas": [{"phx_ref": "abc"}]}
      }))

      diff = JSON.parse(%({
        "joins": {},
        "leaves": {"user1": {"metas": [{"phx_ref": "abc"}]}}
      }))

      result = Phoenix::Presence.sync_diff(state, diff,
        on_join: ->(_k : String, _c : JSON::Any?, _n : JSON::Any) { nil },
        on_leave: ->(_k : String, _c : JSON::Any, _l : JSON::Any) { nil },
      )

      result["user1"]?.should be_nil
    end
  end

  describe "instance API" do
    it "tracks state via on_join / on_leave / on_sync" do
      ch = Phoenix::Channel.new("room:lobby", JSON.parse("{}"))
      presence = Phoenix::Presence.new(ch)

      joined_keys = [] of String
      left_keys = [] of String
      synced = false

      presence.on_join { |key, _cur, _new| joined_keys << key }
      presence.on_leave { |key, _cur, _left| left_keys << key }
      presence.on_sync { synced = true }

      # Simulate presence_state event
      state_payload = JSON.parse(%({
        "user1": {"metas": [{"phx_ref": "a1"}]},
        "user2": {"metas": [{"phx_ref": "b1"}]}
      }))
      ch.trigger("presence_state", state_payload)

      joined_keys.should eq(["user1", "user2"])
      synced.should be_true

      presence.list.size.should eq(2)
    end
  end
end
