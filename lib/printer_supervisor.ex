defmodule PrintSupervisor do
  use Supervisor

  def start_link(num_workers) do
    IO.puts "Starting PrintSupervisor ..."
    Supervisor.start_link(__MODULE__, num_workers, name: __MODULE__)
    |> elem(1)
  end

  def init(num_workers) do
    children =
      Enum.map(1..num_workers, fn id ->
        %{
          id: id,
          start: {Print, :start_link, [id]}
        }
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end


  def get_message_count(pid) do
    GenServer.call(pid, :message_count)
  end

  def count() do
    Supervisor.count_children(__MODULE__)
    |> Map.fetch!(:active)
  end

  def get_worker_pid(id) do
    Supervisor.which_children(__MODULE__)
    |> Enum.find(fn {i, _, _, _} -> i == id end)
    |> elem(1)
  end

  def get_worker_id(pid) do
    Supervisor.which_children(__MODULE__)
    |> Enum.find(fn {_, i, _, _} -> i == pid end)
    |> elem(0)
  end

  def get_all_pids() do
    Enum.map(1..count(), fn i -> get_worker_pid(i) end)
  end
end
