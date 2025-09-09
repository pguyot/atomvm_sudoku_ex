defmodule AtomvmSudokuEx.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {AtomvmSudokuEx.Main, []}
    ]

    opts = [strategy: :one_for_one, name: AtomvmSudokuEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end