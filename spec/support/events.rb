# frozen_string_literal: true

# Host event contract for standalone extension specs; LegionIO owns the production bus.
module Legion
  module Events
    def self.on(name, &handler)
      @listeners ||= Hash.new { |hash, key| hash[key] = [] }
      @listeners[name] << handler
    end

    def self.emit(name, **event)
      @listeners&.fetch(name, [])&.each { |handler| handler.call(event) }
    end
  end
end
