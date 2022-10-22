:ets.new(:integration_tests, [:set, :public, :named_table])

ExWs.GenTcpFake.start_link()
ExWs.Supervisor.start_link(Application.get_all_env(:exws))

ExUnit.start(exclude: [:skip])
