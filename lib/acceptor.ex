defmodule ExWs.Acceptor do
	use Task, restart: :transient
	require Logger

	def start_link(opts) do
		Task.start_link(__MODULE__, :run, opts)
	end

	def run(opts) do
		accept_loop(opts[:socket], opts[:handler])
	end

	defp accept_loop(listen_socket, handler) do
		case :gen_tcp.accept(listen_socket) do
			{:ok, client_socket} ->
				opts = {client_socket, ExWs.Reader.new()}
				case GenServer.start(handler, opts) do
					{:ok, pid} ->
						:gen_tcp.controlling_process(client_socket, pid)
						GenServer.cast(pid, :ready)
					err -> Logger.error("handler start: #{inspect(err)}")
				end
			{:error, err} -> Logger.error("accept: #{inspect(err)}")
		end
		accept_loop(listen_socket, handler)
	end
end
