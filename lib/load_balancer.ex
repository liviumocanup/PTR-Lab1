defmodule LoadBalancer do
  use GenServer

  @load_threshold 10
  @idle_threshold 1
  @check_idle_interval 5000

  def start_link() do
    IO.puts "Starting LoadBalancer ..."
    pid = GenServer.start_link(__MODULE__, [])
    |> elem(1)
    Process.register(pid, __MODULE__)
  end

  def init(args) do
    WorkerPoolManager.start_link()
    schedule_check_idle()
    ReadSupervisor.start_link()
    {:ok, args}
  end

  def handle_call(msg, _from, state) do
    printer_pid = least_connected_printer()
    IO.puts "Least connected printer: #{inspect find_id(printer_pid)} with #{inspect Process.info(printer_pid)[:message_queue_len]} messages"
    send(printer_pid, {find_id(printer_pid), msg})
    {:reply, :ok, state}
  end

  def handle_info(:check_idle, state) do
    printer_pid = least_connected_printer()
    check_idle(printer_pid)
    schedule_check_idle()
    {:noreply, state}
  end

  def print(msg) do
    GenServer.call(GenServer.whereis(__MODULE__), msg)
  end

  defp schedule_check_idle do
    Process.send_after(self(), :check_idle, @check_idle_interval)
  end

  defp check_idle(pid) do
    if Process.info(pid)[:message_queue_len] > @load_threshold do
      IO.puts "\n\n====>>> Printers are overloaded."
      WorkerPoolManager.increase_workers(1)
    else
      if Process.info(pid)[:message_queue_len] < @idle_threshold do
        IO.puts "\n\n====>>> Printers are idle."
        WorkerPoolManager.decrease_workers(1)
      end
    end
  end

  defp least_connected_printer() do
    printer_pids = get_all_pids()
    counts = all_printers_queue_len(printer_pids)
    Enum.min_by(counts, fn {_, count} -> count end)
    |> elem(0)
  end

  defp all_printers_queue_len(printer_pids) do
    Enum.map(printer_pids, fn pid ->
      {pid, Process.info(pid)[:message_queue_len]}
    end)
  end

  defp all_printers_message_count(printer_pids) do
    Enum.map(printer_pids, fn pid ->
      {pid, PrintSupervisor.get_message_count(pid)}
    end)
  end

  defp find_id(printer_pid) do
    PrintSupervisor.get_worker_id(printer_pid)
  end

  defp get_all_pids() do
    PrintSupervisor.get_all_pids()
  end
end
