module Phoenix
  class Presence
    record Entry, key : String, metas : Array(::JSON::Any)

    @state = ::JSON::Any.new({} of String => ::JSON::Any)
    @pending_diffs = [] of ::JSON::Any
    @join_ref : String? = nil
    @on_join_callbacks = [] of Proc(String, ::JSON::Any?, ::JSON::Any, Nil)
    @on_leave_callbacks = [] of Proc(String, ::JSON::Any, ::JSON::Any, Nil)
    @on_sync_callbacks = [] of Proc(Nil)

    def initialize(@channel : Channel)
      @channel.on("presence_state") { |payload| handle_state(payload) }
      @channel.on("presence_diff") { |payload| handle_diff(payload) }
    end

    def on_join(&callback : String, ::JSON::Any?, ::JSON::Any ->) : Nil
      @on_join_callbacks << callback
    end

    def on_leave(&callback : String, ::JSON::Any, ::JSON::Any ->) : Nil
      @on_leave_callbacks << callback
    end

    def on_sync(&callback : ->) : Nil
      @on_sync_callbacks << callback
    end

    def list : Array(Entry)
      entries = [] of Entry
      if hash = @state.as_h?
        hash.each do |key, presence|
          metas = presence["metas"]?.try(&.as_a?) || [] of ::JSON::Any
          entries << Entry.new(key: key, metas: metas)
        end
      end
      entries
    end

    def list(&chooser : String, Entry -> T) : Array(T) forall T
      list.map { |entry| chooser.call(entry.key, entry) }
    end

    # Static sync algorithms — match the Phoenix JS client exactly

    def self.sync_state(
      current_state : ::JSON::Any,
      new_state : ::JSON::Any,
      on_join : Proc(String, ::JSON::Any?, ::JSON::Any, Nil),
      on_leave : Proc(String, ::JSON::Any, ::JSON::Any, Nil),
    ) : ::JSON::Any
      joins = {} of String => ::JSON::Any
      leaves = {} of String => ::JSON::Any

      # Find leaves: in current but not in new
      if cur_hash = current_state.as_h?
        cur_hash.each do |key, presence|
          unless new_state.as_h?.try(&.has_key?(key))
            leaves[key] = presence
          end
        end
      end

      # Find joins: in new, check for meta changes
      if new_hash = new_state.as_h?
        new_hash.each do |key, new_presence|
          cur_presence = current_state.as_h?.try(&.[key]?)

          if cur_presence
            new_refs = (new_presence["metas"]?.try(&.as_a?) || [] of ::JSON::Any).map { |m| m["phx_ref"]?.try(&.as_s?) }
            cur_refs = (cur_presence["metas"]?.try(&.as_a?) || [] of ::JSON::Any).map { |m| m["phx_ref"]?.try(&.as_s?) }

            joined_metas = (new_presence["metas"]?.try(&.as_a?) || [] of ::JSON::Any).select { |m|
              !cur_refs.includes?(m["phx_ref"]?.try(&.as_s?))
            }

            left_metas = (cur_presence["metas"]?.try(&.as_a?) || [] of ::JSON::Any).select { |m|
              !new_refs.includes?(m["phx_ref"]?.try(&.as_s?))
            }

            if joined_metas.size > 0
              joins[key] = ::JSON.parse({"metas" => joined_metas}.to_json)
            end

            if left_metas.size > 0
              leaves[key] = ::JSON.parse({"metas" => left_metas}.to_json)
            end
          else
            joins[key] = new_presence
          end
        end
      end

      diff = ::JSON.parse({"joins" => joins, "leaves" => leaves}.to_json)
      sync_diff(current_state, diff, on_join: on_join, on_leave: on_leave)
    end

    def self.sync_diff(
      state : ::JSON::Any,
      diff : ::JSON::Any,
      on_join : Proc(String, ::JSON::Any?, ::JSON::Any, Nil),
      on_leave : Proc(String, ::JSON::Any, ::JSON::Any, Nil),
    ) : ::JSON::Any
      result = state.as_h?.try(&.clone) || {} of String => ::JSON::Any

      # Process joins
      if joins = diff["joins"]?.try(&.as_h?)
        joins.each do |key, new_presence|
          cur_presence = result[key]?
          result[key] = new_presence

          if cur_presence
            # Preserve existing metas not in the join
            joined_refs = (new_presence["metas"]?.try(&.as_a?) || [] of ::JSON::Any).map { |m| m["phx_ref"]?.try(&.as_s?) }
            cur_metas = (cur_presence["metas"]?.try(&.as_a?) || [] of ::JSON::Any).select { |m|
              !joined_refs.includes?(m["phx_ref"]?.try(&.as_s?))
            }
            all_metas = cur_metas + (new_presence["metas"]?.try(&.as_a?) || [] of ::JSON::Any)
            result[key] = ::JSON.parse({"metas" => all_metas}.to_json)
          end

          on_join.call(key, cur_presence, new_presence)
        end
      end

      # Process leaves
      if leaves = diff["leaves"]?.try(&.as_h?)
        leaves.each do |key, left_presence|
          cur_presence = result[key]?
          next unless cur_presence

          refs_to_remove = (left_presence["metas"]?.try(&.as_a?) || [] of ::JSON::Any).map { |m| m["phx_ref"]?.try(&.as_s?) }
          remaining = (cur_presence["metas"]?.try(&.as_a?) || [] of ::JSON::Any).select { |m|
            !refs_to_remove.includes?(m["phx_ref"]?.try(&.as_s?))
          }

          on_leave.call(key, cur_presence, left_presence)

          if remaining.empty?
            result.delete(key)
          else
            result[key] = ::JSON.parse({"metas" => remaining}.to_json)
          end
        end
      end

      ::JSON::Any.new(result)
    end

    private def join_callback : Proc(String, ::JSON::Any?, ::JSON::Any, Nil)
      ->(key : String, cur : ::JSON::Any?, new_p : ::JSON::Any) {
        @on_join_callbacks.each &.call(key, cur, new_p)
        nil
      }
    end

    private def leave_callback : Proc(String, ::JSON::Any, ::JSON::Any, Nil)
      ->(key : String, cur : ::JSON::Any, left : ::JSON::Any) {
        @on_leave_callbacks.each &.call(key, cur, left)
        nil
      }
    end

    private def handle_state(new_state : ::JSON::Any) : Nil
      @state = Presence.sync_state(@state, new_state,
        on_join: join_callback, on_leave: leave_callback)

      @pending_diffs.each do |diff|
        @state = Presence.sync_diff(@state, diff,
          on_join: join_callback, on_leave: leave_callback)
      end
      @pending_diffs.clear
      @join_ref = @channel.join_ref

      @on_sync_callbacks.each &.call
    end

    private def handle_diff(diff : ::JSON::Any) : Nil
      if in_pending_sync_state?
        @pending_diffs << diff
      else
        @state = Presence.sync_diff(@state, diff,
          on_join: join_callback, on_leave: leave_callback)
        @on_sync_callbacks.each &.call
      end
    end

    private def in_pending_sync_state? : Bool
      !@join_ref || @join_ref != @channel.join_ref
    end
  end
end
