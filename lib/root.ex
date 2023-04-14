defmodule Root do
  def start do
    DatabaseProxy.start_link()
    Dispatcher.start_link()

    Aggregator.start_link()
    Batcher.start_link()
    ReadSupervisor.start_link()
  end
end
