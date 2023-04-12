defmodule Dispatcher do
  use GenServer

  def start_link do
    pid = GenServer.start_link(__MODULE__, %{id: 0})
    |> elem(1)
    Process.register(pid, __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def dispatch(info) do
    GenServer.cast(__MODULE__, info)
  end

  def handle_cast(info, state) do

    {text, stats} = info

    {id, new_state} = generate_id(state)

    # IO.puts("Starting distribution for #{inspect info}\n\n")

    Task.start(fn -> LoadBalancer.cast(:PrintLB, {text, id}) end)
    Task.start(fn -> LoadBalancer.cast(:SentimentLB, {text, id}) end)
    Task.start(fn -> LoadBalancer.cast(:EngagementLB, {stats, id}) end)

    {:noreply, new_state}
  end

  def generate_id(state) do
    id = state.id + 1
    new_state = Map.put(state, :id, id)

    {id, new_state}
  end
end
