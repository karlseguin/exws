defmodule ExWs.Handshake.Errors do
	def build(code, message) do
		data = [
			"HTTP/1.1 ", to_string(code), " ", phrase(code), "\r\n",
			"Error: ", message, "\r\n",
			"Content-Length: 0\r\n",
			"\r\n"
		]
		{:invalid, :erlang.iolist_to_binary(data)}
	end

	defp phrase(400), do: "Bad Request"
	defp phrase(_), do: "Server Error"
end

defmodule ExWs.Handshake do
	require Logger

	alias __MODULE__.Errors

	if Mix.env == :test && System.get_env("AB") != "1" do
		@inet ExWs.GenTcpFake
		@gen_tcp ExWs.GenTcpFake
	else
		@inet :inet
		@gen_tcp :gen_tcp
	end

	@invalid_request_line Errors.build(400, "request_line")
	@invalid_path Errors.build(400, "path")
	@invalid_method Errors.build(400, "method")
	@invalid_proto Errors.build(400, "protocol")
	@invalid_headers Errors.build(400, "headers")

	@invalid_key Errors.build(400, "key")
	@invalid_host Errors.build(400, "host")
	@invalid_version Errors.build(400, "version")
	@invalid_upgrade Errors.build(400, "upgrade")
	@invalid_connection Errors.build(400, "connection")

	if Mix.env == :prod do
		@timeout 5000
	else
		@timeout 100
	end

	def read(socket) do
		@inet.setopts(socket, packet: :line)
		with {:ok, request_line} <- read_request_line(socket),
		     {:ok, path} <- verify_request_line(request_line),
		     {:ok, headers} <- read_headers(socket, %{}),
		     :ok <- validate_headers(headers)
		do
			{:ok, path, headers, socket}
		else
			err -> close(socket, err); :closed
		end
	end

	defp read_request_line(socket) do
		case read_line(socket) do
			{:ok, line} -> {:ok, line}
			_ -> @invalid_request_line
		end
	end

	defp verify_request_line(line) do
		with {:ok, line} <- ensure_method(line),
		     {:ok, path, line} <- extract_path(trim_leading(line)),
		     :ok <- ensure_protocol(trim_leading(line))
		do
			{:ok, path}
		end
	end

	defp ensure_method(<<method::binary-size(3), " ", line::binary>>) do
		case string_compare(method, "get") do
			true -> {:ok, line}
			false -> @invalid_method
		end
	end

	defp ensure_method(_line) do
		@invalid_method
	end

	defp extract_path(line) do
		case :binary.split(line, " ") do
			[path, line] -> {:ok, path, line}
			_ -> @invalid_path
		end
	end

	defp ensure_protocol(line) do
		case string_compare(line, "http/1.1") do
			true -> :ok
			false -> @invalid_proto
		end
	end

	defp read_headers(socket, headers) do
		with {:ok, line} when line != "" <- read_line(socket),
		     [name, value] <- :binary.split(line, ":")
		do
			read_headers(socket, set_header(headers, header_downcase(name, []), value))
		else
			{:ok, ""} -> {:ok, headers} # An empty readline means we're done
			{:error, _} = err -> err
			_ -> @invalid_headers
		end
	end

	for {key, name} <- [host: "host", connection: "connection", upgrade: "upgrade", key: "sec-websocket-key", version: "sec-websocket-version"] do
		defp set_header(headers, unquote(name), value) do
			Map.put(headers, unquote(key), String.trim(value))
		end
	end

	defp set_header(headers, _key, _value), do: headers

	defp validate_headers(headers) do
		key = headers[:key]
		host = headers[:host]
		with true <- key not in [nil, ""] || @invalid_key,
		     true <- host not in [nil, ""] || @invalid_host,
		     true <- headers[:version] == "13" || @invalid_version,
		     true <- header_has_value(headers[:upgrade], "websocket") || @invalid_upgrade,
		     true <- header_has_value(headers[:connection], "upgrade") || @invalid_connection
		do
			:ok
		end
	end

	def accept(socket, headers) do
		key = headers[:key]
		accept_key = :sha
		|> :crypto.hash([key, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"])
		|> Base.encode64()

		data = [
			"HTTP/1.1 101 Switching Protocols\r\n",
			"Upgrade: websocket\r\n",
			"Connection: Upgrade\r\n",
			"Sec-WebSocket-Accept: ", accept_key, "\r\n",
			"\r\n"
		]

		@inet.setopts(socket, send_timeout: @timeout)
		@gen_tcp.send(socket, data)
	end

	def reject(socket, err), do: close(socket, err)

	defp read_line(socket) do
		case @gen_tcp.recv(socket, 0, @timeout) do
			{:ok, data} ->
				 # strip out the trailing \r\n
				length = byte_size(data) - 2
				<<data::bytes-size(length), _, _>> = data
				{:ok, data}
			err -> err
		end
	end

	defp close(socket, {:invalid, message}) do
		@inet.setopts(socket, send_timeout: @timeout)
		@gen_tcp.send(socket, message)
		@gen_tcp.close(socket)
	end

	# Probably an error from :gen_tcp
	defp close(socket, err) do
		Logger.error("handshake: #{inspect(err)}")
		@gen_tcp.close(socket)
	end

	defp trim_leading(<<" ", data::binary>>), do: trim_leading(data)
	defp trim_leading(data), do: data

	defp header_has_value(actual, expected) do
		header_has_value(actual, expected, expected)
	end

	defp header_has_value(<<>>, <<>>, _expected), do: true
	defp header_has_value(<<",", _::binary>>, <<>>, _expected), do: true

	defp header_has_value(<<" ", rest::binary>>, <<>>, expected) do
		header_has_value(rest, <<>>, expected)
	end

	defp header_has_value(<<i, input::binary>>, <<t, target::binary>>, expected) do
		case i == t || i + 32 == t do
			true -> header_has_value(input, target, expected)
			false ->
				case :binary.split(input, ",") do
					[_, next] -> header_has_value(trim_leading(next), expected, expected)
					_ -> false
				end
		end
	end

	defp header_has_value(<<_::binary>>, <<>>, _expected), do: false
	defp header_has_value(<<>>, <<_::binary>>, _expected), do: false
	defp header_has_value(nil, _, _expected), do: false
	defp string_compare(<<i, input::binary>>, <<t, target::binary>>) do
		case i == t || i + 32 == t do
			false -> false
			true -> string_compare(input, target)
		end
	end

	defp string_compare(<<>>, <<>>), do: true
	defp string_compare(<<" ", input::binary>>, <<>>), do: string_compare(input, <<>>)
	defp string_compare(<<_::binary>>, <<>>), do: false
	defp string_compare(<<>>, <<_::binary>>), do: false

	# The HTML headers that we care about have very few legal values
	defp header_downcase(<<>>, acc) do
		acc |> Enum.reverse() |> :erlang.list_to_binary()
	end

	defp header_downcase(<<c, input::binary>>, acc) do
		c = case c >= ?A && c <= ?Z do
			true -> c + 32
			false -> c
		end
		header_downcase(input, [c | acc])
	end
end
