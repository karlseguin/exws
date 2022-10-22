defmodule ExWs.Server do
	use Supervisor

	if Mix.env in [:ab, :test] do
		def start_for_tests() do
			{:ok, _pid} = start_link(Application.get_all_env(:exws))
			:timer.sleep(:infinity)
		end
	end

	def start_link(config) do
		Supervisor.start_link(__MODULE__, config)
	end

	def init(config) do
		port = Keyword.fetch!(config, :port)
		handler = Keyword.fetch!(config, :handler)
		opts = [:binary, packet: :raw, active: false, reuseaddr: true, backlog: 1024]

		{port, opts} = case port do
			{:local, _} = unix -> {0, Keyword.put(opts, :ifaddr, unix)}
			port -> {port, opts}
		end

		{:ok, socket} = :gen_tcp.listen(port, opts)

		opts = [[socket: socket, handler: handler]]
		children = [
			Supervisor.child_spec({ExWs.Acceptor, opts}, id: :ws_acceptor_1),
			Supervisor.child_spec({ExWs.Acceptor, opts}, id: :ws_acceptor_2),
			Supervisor.child_spec({ExWs.Acceptor, opts}, id: :ws_acceptor_3),
			Supervisor.child_spec({ExWs.Acceptor, opts}, id: :ws_acceptor_4)
		]
		Supervisor.init(children, strategy: :one_for_one)
	end
end
