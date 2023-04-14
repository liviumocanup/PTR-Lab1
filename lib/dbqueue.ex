defmodule DatabaseProxy do
  use GenServer

  def start_link() do
    pid = GenServer.start_link(__MODULE__, [])
    |> elem(1)
    Process.register(pid, __MODULE__)
  end

  def init(_) do
    Database.start_link()
    {:ok, %{queue: :queue.new(), paused: false}}
  end

  def add_item(item) do
    GenServer.cast(__MODULE__, {:add_item, item})
  end

  def toggle_pause() do
    GenServer.call(__MODULE__, :toggle_pause)
  end

  def get_tweets() do
    GenServer.call(__MODULE__, :get)
  end

  def handle_cast({:add_item, item}, %{queue: queue, paused: paused} = state) do
    if paused do
      {:noreply, %{state | queue: :queue.in(item, queue)}}
    else
      Database.store_tweet_and_user(item)
      {:noreply, state}
    end
  end

  def handle_call(:toggle_pause, _from, %{paused: paused} = state) do
    new_state = %{state | paused: !paused}
    {:reply, {:ok, !paused}, process_queue(new_state)}
  end

  def handle_call(:get, _from, %{paused: paused} = state) do
    reply = if paused do
      IO.puts("Database currently unavailable.")
    else
      Database.get_tweets()
    end
    {:reply, reply, state}
  end

  defp process_queue(%{queue: queue, paused: false} = state) do
    case :queue.out(queue) do
      {{:value, item}, new_queue} ->
        Database.store_tweet_and_user(item)
        process_queue(%{state | queue: new_queue})

      {:empty, _} ->
        state
    end
  end

  defp process_queue(state) do
    state
  end
end
