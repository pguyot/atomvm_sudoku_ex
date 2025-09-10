import Config

root = "#{__DIR__}/../"

config :popcorn,
  add_tracing: false,
  out_dir: "#{root}/static/wasm"
