# Generous waits for messages: a loaded machine delays them well past ExUnit's 100 ms
# default; a message that does arrive ends the wait at once.
ExUnit.start(assert_receive_timeout: 1_000)
Ecto.Adapters.SQL.Sandbox.mode(Ziwoas.Repo, :manual)
