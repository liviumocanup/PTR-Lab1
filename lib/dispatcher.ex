defmodule Dispatcher do
  use GenServer

  def start_link do
    pid = GenServer.start_link(__MODULE__, %{id: 0})
    |> elem(1)
    Process.register(pid, __MODULE__)
  end

  def init(state) do
    EngagementTracker.start_link()

    print_sup_name = GenericSupervisor.generate_supervisor_name(Print)
    eng_sup_name = GenericSupervisor.generate_supervisor_name(Engagement)
    sent_sup_name = GenericSupervisor.generate_supervisor_name(Sentiment)
    censor_sup_name = GenericSupervisor.generate_supervisor_name(Censor)

    GenericSupervisor.start_link(Print, 3)
    GenericSupervisor.start_link(Engagement, 3)
    GenericSupervisor.start_link(Sentiment, 3)
    GenericSupervisor.start_link(Censor, 3)

    w1 = WorkerPoolManager.start_link(print_sup_name, Print)

    true = LoadBalancer.start_link(print_sup_name, w1)
    true = LoadBalancer.start_link(eng_sup_name, nil)
    true = LoadBalancer.start_link(sent_sup_name, nil)
    true = LoadBalancer.start_link(censor_sup_name, nil)
    {:ok, state}
  end

  def dispatch(info) do
    GenServer.cast(__MODULE__, info)
  end

  def handle_cast(info, state) do

    {text, stats} = info

    {id, new_state} = generate_id(state)

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
