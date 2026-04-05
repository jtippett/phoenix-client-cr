module Phoenix
  class Error < Exception; end

  class ClosedError < Error
    def initialize
      super("Cannot push to closed socket")
    end
  end

  class AlreadyJoinedError < Error
    def initialize(topic : String)
      super("Channel #{topic} has already been joined — create a new channel instance")
    end
  end
end
