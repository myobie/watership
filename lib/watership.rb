require "bunny"
require "json"
require "watership/version"

module Watership
  CONNECTION_EXCEPTIONS = [
    Bunny::ClientTimeout,
    Bunny::NetworkFailure,
    Bunny::PossibleAuthenticationFailureError,
    Bunny::TCPConnectionFailed
  ]

  class << self
    def environment=(env)
      @env = env
    end

    def config=(uri)
      @config = uri
    end

    def enqueue(options = {})
      options  = options.dup
      message  = options.delete(:message)
      name     = options.delete(:name)
      fallback = options.delete(:fallback)

      queue = connect_with_queue(name, options)
      queue.publish(JSON.generate(message))
    rescue StandardError => exception
      fallback.call if fallback
      notify(exception)
      logger.error(exception.class.name)
    end

    def connect_with_queue(name, options = {})
      channel.queue(name, { durable: true }.merge(options)) if channel
    end

    def reconnect
      Thread.current[:buuny_channel] = nil
      $bunny_connection = nil
      channel
      true
    end

    def channel
      Thread.current[:bunny_channel] ||= connection.create_channel
    rescue *CONNECTION_EXCEPTIONS => exception
      notify(exception)
      Thread.current[:bunny_channel] = nil
    end

    def connection
      $bunny_connection ||= Bunny.new(@config).tap { |bunny| bunny.start }
    end

    def notify(exception)
      Bugsnag.notify(exception) if defined?(Bugsnag) && @env == 'production'
      Airbrake.notify_or_ignore(exception) if defined?(Airbrake) && @env == 'production'
    end

    def logger=(logger)
      @logger = logger
    end

    def logger
      @logger ||= defined?(Rails) ? Rails.logger : Logger.new(STDOUT)
    end
  end
end
