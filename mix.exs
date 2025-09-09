defmodule AtomvmSudokuEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :atomvm_sudoku_ex,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [
        build_wasm: ["popcorn.build_runtime --target wasm", "popcorn.cook"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [],
      mod: {AtomvmSudokuEx.Application, []}
    ]
  end

  defp deps do
    [
      {:popcorn, "~> 0.1.0"}
    ]
  end
end