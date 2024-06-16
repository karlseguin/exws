defmodule ExWs.Tests.WS do
	import ExUnit.Assertions

	alias __MODULE__

	defstruct [:socket, :status, :headers]

	def connect(port) do
		{:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
		%WS{socket: socket}
	end

	def handshake(port, path, headers \\ %{})

	def handshake(port, path, headers) when is_integer(port) do
		port
		|> connect()
		|> handshake(path, headers)
	end

	def handshake(ws, path, headers) do
		socket = ws.socket
		:ok = :gen_tcp.send(socket, "GET #{path} HTTP/1.1\r\n")
		:ok = :gen_tcp.send(socket, "upgrade: WEBsocKet\r\n")
		:ok = :gen_tcp.send(socket, "connection: upgrade\r\n")
		:ok = :gen_tcp.send(socket, "sec-websocket-version: 13\r\n")
		:ok = :gen_tcp.send(socket, "host: test.openmymind.net\r\n")
		:ok = :gen_tcp.send(socket, "sec-websocket-key: #{Base.encode64(Integer.to_string(:rand.uniform(1_000_000) + 1_000_000))}\r\n")
		Enum.each(headers, fn {k, v} -> :ok = :gen_tcp.send(socket, "#{k}: #{v}\r\n") end)
		:ok = :gen_tcp.send(socket, "\r\n")

		:inet.setopts(socket, packet: :http)
		{:ok, {:http_response, {1, 1}, status, _}} = :gen_tcp.recv(socket, 0, 1000)
		headers = Enum.reduce_while(1..100, %{}, fn _, headers ->
			case :gen_tcp.recv(socket, 0, 100) do
				{:ok, :http_eoh} -> {:halt, headers}
				{:ok, {:http_header, _, name, _, value}} -> {:cont, Map.put(headers, String.downcase(to_string(name)), to_string(value))}
				err -> flunk "handshake response line: #{inspect err}"
			end
		end)
		:inet.setopts(socket, packet: :raw)
		%WS{ws | status: status, headers: headers}
	end

	def closed?(%{socket: socket}) do
		closed?(socket)
	end

	def closed?(socket) do
		{:error, :closed} == :gen_tcp.recv(socket, 0, 10)
	end

	def read_close(%{socket: socket}) do
		{8, <<code::big-16, message::binary>>} = read(socket)
		assert closed?(socket) == true
		{code, message}
	end

	def read(%{socket: socket}), do: read(socket)

	def read(socket) do
		{:ok, data} = :gen_tcp.recv(socket, 2, 1000)
		# fin, rsv, rsv2, rsv3, op::4, mask...
		<<1::1, _::1, _::1, _::1, op::4, 0::1, len::7>> = data

		len = case len do
			127 -> {:ok, <<len::big-64>>} = :gen_tcp.recv(socket, 8, 1000); len
			126 -> {:ok, <<len::big-16>>} = :gen_tcp.recv(socket, 2, 1000); len
			_ -> len
		end

		case len == 0 do
			true -> {op, ""}
			false ->
				{:ok, data} = :gen_tcp.recv(socket, len, 1000)
				{op, data}
		end
	end

	def read_bin(s) do
		{2, data} = read(s)
		data
	end

	def read_json(s) do
		{op, data} = read(s)
		assert op == 2 || op == 1
		:jiffy.decode(data)
	end

	def read_json(s, prefix) do
		{op, <<^prefix, data::binary>>} = read(s)
		assert op == 2 || op == 1
		:jiffy.decode(data)
	end

	def empty?(%{socket: socket}), do: empty?(socket)

	def empty?(socket) do
		case :gen_tcp.recv(socket, 1, 20) do
			{:error, :timeout} -> true
			other -> other
		end
	end

	def write(%{socket: socket} = ws, data) do
		write(socket, data)
		ws
	end

	def write(socket, data) when is_map(data) do
		write(socket, :jiffy.encode(data))
	end

	def write(socket, data) do
		length = :erlang.iolist_size(data)

		# MSB has to be 1 to indicate that our data is masked
		length = cond do
			length < 125 -> 128 + length
			length < 65536 -> <<254, length::big-integer-16>>
			true  -> <<255, length::big-integer-64>>
		end

		data = [
			130,  # fin + bin data
			length,
			<<0, 0, 0, 0>>,    # mask of zero (teehee)
			data
		]
		:gen_tcp.send(socket, data)
	end


	def kill(ws), do: :gen_tcp.close(ws.socket)
end
