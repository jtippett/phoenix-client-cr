module Phoenix
  class Timer
    BACKOFF_STEPS = [1, 2, 5, 10]

    DEFAULT_BACKOFF = ->(tries : Int32) : Time::Span {
      BACKOFF_STEPS.fetch(tries - 1, BACKOFF_STEPS.last).seconds
    }

    @tries : Int32 = 0
    @generation : Int32 = 0

    def initialize(
      @callback : Proc(Nil),
      @timer_calc : Proc(Int32, Time::Span),
    )
    end

    def schedule_timeout : Nil
      @generation += 1
      @tries += 1
      gen = @generation
      delay = @timer_calc.call(@tries)
      spawn do
        sleep delay
        @callback.call if gen == @generation
      end
    end

    def reset : Nil
      @generation += 1
      @tries = 0
    end
  end
end
