require "../spec_helper"

describe Phoenix::Push do
  describe "#receive" do
    it "is chainable" do
      push = Phoenix::Push.new(
        event: "test",
        payload: JSON.parse("{}"),
        timeout: 5.seconds,
      )

      result = push
        .receive("ok") { |_resp| }
        .receive("error") { |_resp| }
        .receive("timeout") { |_| }

      result.should be(push)
    end

    it "triggers matching callback on response" do
      push = Phoenix::Push.new(
        event: "test",
        payload: JSON.parse("{}"),
        timeout: 5.seconds,
      )

      received = nil
      push.receive("ok") { |resp| received = resp }

      reply_payload = JSON.parse(%({"status": "ok", "response": {"data": 1}}))
      push.trigger("ok", reply_payload["response"])

      received.should_not be_nil
      received.try &.["data"].as_i.should eq(1)
    end

    it "does not trigger non-matching callbacks" do
      push = Phoenix::Push.new(
        event: "test",
        payload: JSON.parse("{}"),
        timeout: 5.seconds,
      )

      ok_called = false
      error_called = false
      push.receive("ok") { |_| ok_called = true }
      push.receive("error") { |_| error_called = true }

      push.trigger("error", JSON.parse("{}"))

      ok_called.should be_false
      error_called.should be_true
    end
  end

  describe "#trigger_timeout" do
    it "fires timeout callbacks" do
      push = Phoenix::Push.new(
        event: "test",
        payload: JSON.parse("{}"),
        timeout: 5.seconds,
      )

      timed_out = false
      push.receive("timeout") { |_| timed_out = true }
      push.trigger_timeout

      timed_out.should be_true
    end
  end

  describe "#reset" do
    it "allows callbacks to fire again after reset" do
      push = Phoenix::Push.new(
        event: "test",
        payload: JSON.parse("{}"),
        timeout: 5.seconds,
      )

      count = 0
      push.receive("ok") { |_| count += 1 }

      push.trigger("ok", JSON.parse("{}"))
      push.trigger("ok", JSON.parse("{}"))
      count.should eq(1) # only fires once

      push.reset
      push.trigger("ok", JSON.parse("{}"))
      count.should eq(2) # fires again after reset
    end
  end
end
