defmodule LoadBalancer do
  use GenServer

  @load_threshold 10
  @idle_threshold 1
  @check_idle_interval 5000

  def start_link(supervisor_name, wpm_pid) do
    lb_name = generate_name(supervisor_name)
    supervisor_name = String.to_atom(supervisor_name)
    IO.puts "Starting LoadBalancer for #{inspect supervisor_name}..."
    pid = GenServer.start_link(__MODULE__, %{supervisor_name: supervisor_name, sup_pid: GenServer.whereis(supervisor_name), wpm_pid: wpm_pid, lb_name: lb_name})
    |> elem(1)
    Process.register(pid, lb_name)
  end

  def init(state) do
    if state.wpm_pid != nil do
      schedule_check_idle()
    end

    {:ok, state}
  end

  def handle_cast({info, id}, state) do
    worker_pid = least_connected_worker(state)
    GenServer.cast(worker_pid, {info, id})
    {:noreply, state}
  end

  def handle_call(info, _from, state) do
    worker_pid = least_connected_worker(state)
    # IO.puts "Least connected worker: #{inspect find_id(worker_pid, state)} with #{inspect Process.info(worker_pid)[:message_queue_len]} messages"
    response = GenServer.call(worker_pid, {find_id(worker_pid, state), info})
    {:reply, response, state}
  end

  def handle_info(:check_idle, state) do
    worker_pid = least_connected_worker(state)
    check_idle(worker_pid, state)
    schedule_check_idle()
    {:noreply, state}
  end

  def process(lb_name, info) do
    GenServer.call(GenServer.whereis(lb_name), info)
  end

  def cast(lb_name, {info, id}) do
    GenServer.cast(GenServer.whereis(lb_name), {info, id})
  end

  def schedule_check_idle do
    Process.send_after(self(), :check_idle, @check_idle_interval)
  end

  defp check_idle(pid, state) do
    if Process.info(pid)[:message_queue_len] > @load_threshold do
      IO.puts "\n\n====>>>#{state.lb_name}: Workers are overloaded."
      WorkerPoolManager.increase_workers(state.wpm_pid, 1)
    else
      if Process.info(pid)[:message_queue_len] < @idle_threshold and Process.info(pid)[:message_queue_len] > 1 do
        IO.puts "\n\n====>>>#{state.lb_name}: Workers are idle."
        WorkerPoolManager.decrease_workers(state.wpm_pid, 1)
      end
    end
  end

  defp least_connected_worker(state) do
    worker_pids = get_all_pids(state)
    counts = all_workers_queue_len(worker_pids)
    Enum.min_by(counts, fn {_, count} -> count end)
    |> elem(0)
  end

  defp all_workers_queue_len(worker_pids) do
    Enum.map(worker_pids, fn pid ->
      {pid, Process.info(pid)[:message_queue_len]}
    end)
  end

  # defp all_printers_message_count(printer_pids) do
  #   Enum.map(printer_pids, fn pid ->
  #     {pid, PrintSupervisor.get_message_count(pid)}
  #   end)
  # end

  defp find_id(worker_pid, state) do
    GenericSupervisor.get_worker_id(state.sup_pid, worker_pid)
  end

  defp get_all_pids(state) do
    GenericSupervisor.get_all_pids(state.sup_pid)
  end

  defp generate_name(supervisor_name) do
    String.to_atom(String.replace(supervisor_name, "Supervisor", "LB"))
  end
end
