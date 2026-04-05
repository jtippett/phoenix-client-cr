require "../spec_helper"

describe Phoenix::Timer do
  describe "#schedule_timeout" do
    it "calls the callback after the computed delay" do
      called = false
      timer = Phoenix::Timer.new(
        callback: -> { called = true },
        timer_calc: ->(tries : Int32) { 1.millisecond },
      )

      timer.schedule_timeout
      sleep 10.milliseconds
      called.should be_true
    end

    it "increments tries on each schedule" do
      recorded_tries = [] of Int32
      timer = Phoenix::Timer.new(
        callback: -> { },
        timer_calc: ->(tries : Int32) { recorded_tries << tries; 1.millisecond },
      )

      timer.schedule_timeout
      sleep 5.milliseconds
      timer.schedule_timeout
      sleep 5.milliseconds
      recorded_tries.should eq([1, 2])
    end
  end

  describe "#reset" do
    it "resets the try count" do
      recorded_tries = [] of Int32
      timer = Phoenix::Timer.new(
        callback: -> { },
        timer_calc: ->(tries : Int32) { recorded_tries << tries; 1.millisecond },
      )

      timer.schedule_timeout
      sleep 5.milliseconds
      timer.schedule_timeout
      sleep 5.milliseconds
      timer.reset

      timer.schedule_timeout
      sleep 5.milliseconds
      recorded_tries.should eq([1, 2, 1])
    end
  end

  describe "DEFAULT_BACKOFF" do
    it "returns increasing durations" do
      calc = Phoenix::Timer::DEFAULT_BACKOFF
      calc.call(1).should eq(1.second)
      calc.call(2).should eq(2.seconds)
      calc.call(3).should eq(5.seconds)
      calc.call(4).should eq(10.seconds)
      calc.call(5).should eq(10.seconds)
      calc.call(100).should eq(10.seconds)
    end
  end
end
