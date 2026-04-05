module Phoenix
  class Push
    getter event : String
    getter payload : JSON::Any
    getter ref : String?
    getter timeout : Time::Span

    @receive_hooks = {} of String => Array(Proc(JSON::Any, Nil))
    @timeout_hooks = [] of Proc(Nil)
    @triggered = false
    @timeout_triggered = false

    def initialize(@event : String, @payload : JSON::Any, @timeout : Time::Span)
    end

    # Chainable callback registration.
    # Status is "ok", "error", or "timeout".
    # All callbacks receive a JSON::Any argument (ignored for timeout).
    def receive(status : String, &callback : JSON::Any ->) : self
      if status == "timeout"
        wrapped = callback
        @timeout_hooks << -> { wrapped.call(JSON::Any.new(nil)) }
      else
        @receive_hooks[status] ||= [] of Proc(JSON::Any, Nil)
        @receive_hooks[status] << callback
      end
      self
    end

    def trigger(status : String, response : JSON::Any) : Nil
      return if @triggered
      @triggered = true
      @receive_hooks[status]?.try &.each &.call(response)
    end

    def trigger_timeout : Nil
      return if @triggered || @timeout_triggered
      @timeout_triggered = true
      @timeout_hooks.each &.call
    end

    def reset : Nil
      @triggered = false
      @timeout_triggered = false
    end

    # Set by Channel when sending
    def ref=(@ref : String?)
    end
  end
end
