defmodule ExWs.GenTcpFake do
	use GenServer

	@name __MODULE__

	def start_link() do
		GenServer.start_link(__MODULE__, [], name: @name)
	end

	def init(_), do: {:ok, do_reset()}
	def real(), do: GenServer.cast(@name, :real)
	def fake(), do: GenServer.cast(@name, :fake)
	def reset(buffer \\ []), do: GenServer.cast(@name, {:reset, buffer})
	def close(socket), do: GenServer.call(@name, {:close, socket})
	def send(socket, data), do: GenServer.call(@name, {:send, socket, data})
	def setopts(socket, opts), do: GenServer.call(@name, {:setops, socket, opts})
	def sent(), do: GenServer.call(@name, :sent)
	def closed?(), do: GenServer.call(@name, :closed?)
	def recv(socket, len, timeout \\ 0) do
		GenServer.call(@name, {:recv, socket, len, timeout})
	catch
		:exit, {:timeout, _} -> {:error, :timeout}
	end

	def handle_cast(:real, state) do
		{:noreply, %{state | fake: false}}
	end

	def handle_cast(:fake, state) do
		{:noreply, %{state | fake: true}}
	end

	def handle_cast({:reset, buffer}, %{fake: true}) do
		{:noreply, do_reset(buffer)}
	end

	def handle_call({:close, _socket}, _from, %{fake: true} = state) do
		{:reply, :ok, %{state | closed: true}}
	end

	def handle_call({:close, socket}, _from, %{fake: false} = state) do
		:gen_tcp.close(socket)
		{:reply, :ok, state}
	end

	def handle_call({:setops, _socket, _opts}, _from, %{fake: true} = state) do
		{:reply, :ok, state}
	end

	def handle_call({:setops, socket, opts}, _from, %{fake: false} = state) do
		:inet.setopts(socket, opts)
		{:reply, :ok, state}
	end

	def handle_call({:send, _socket, data}, _from, %{fake: true} = state) do
		{:reply, :ok, %{state | sent: [state.sent, data]}}
	end

	def handle_call({:send, socket, data}, _from, %{fake: false} = state) do
		:gen_tcp.send(socket, data)
		{:reply, :ok, state}
	end

	def handle_call(:sent, _from, %{fake: true} = state) do
		{:reply, :erlang.iolist_to_binary(state.sent), %{state | sent: []}}
	end

	def handle_call({:recv, _socket, _len, _timeout}, _from, %{fake: true} = state) do
		[data | buffer] = state.buffer

		data = case data do
			:closed -> {:error, :closed}
			data -> {:ok, data}
		end

		{:reply, data, %{state | buffer: buffer}}
	end

	def handle_call({:recv, socket, len, timeout}, _from, %{fake: false} = state) do
		{:reply, :gen_tcp.recv(socket, len, timeout), state}
	end

	def handle_call(:closed?, _from, %{fake: true} = state) do
		{:reply, state.closed, %{state | closed: false}}
	end

	defp do_reset(buffer \\ []) do
		%{
			sent: [],
			fake: true,
			closed: false,
			buffer: List.flatten(buffer),
		}
	end

end
