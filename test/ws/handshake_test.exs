defmodule ExWs.Tests.Hanshake do
	use ExWs.Tests
	alias ExWs.GenTcpFake

	setup_all do
		ExWs.GenTcpFake.fake()
	end

	test "invalid method" do
		for method <- ["", " ", "POST", "DELETE", "post", "g_et", " get"] do
			assert_error(["#{method} / http/1.1\r\n"], "method")
		end
	end

	test "invalid path" do
		for path <- ["" , " ",] do
			assert_error(["GET #{path} http/1.1\r\n"], "path")
		end
	end

	test "invalid protocol" do
		for protocol <- ["http/1.0" , "http/1.1a", "", " "] do
			assert_error(["get / #{protocol}\r\n"], "protocol")
		end
	end

	test "invalid headers" do
		for headers <- ["hi\r\n", "over 9000\r\n"] do
			assert_error([request_line(), headers], "headers")
		end
	end

	@tag capture_log: true
	test "closed on header reading" do
		assert_closed([request_line(), :closed])
		assert_closed([request_line(), "header: value\r\n", :closed])
	end

	test "error on missing key" do
		assert_error([request_line(), "header: value\r\n", "\r\n"], "key")
	end

	test "error on missing host" do
		assert_error([request_line(), "sec-websocket-key: 123\r\n", "\r\n"], "host")
	end

	test "error on missing or invalid version" do
		valid = [request_line(), "sec-websocket-key: 1\r\n", "host: a\r\n"]
		assert_error([valid, "\r\n"], "version")
		assert_error([valid, "sec-websocket-version: \r\n", "\r\n"], "version")
		assert_error([valid, "sec-websocket-version: 11", "\r\n"], "version")
		assert_error([valid, "sec-websocket-version: 12", "\r\n"], "version")
		assert_error([valid, "sec-websocket-version: thirteen", "\r\n"], "version")
	end

	test "error on missing or invalid upgrade" do
		valid = [request_line(), "SEC-WEBSOCKET-KEY:  longer \r\n", "HOST:   a longer host \r\n", "sec-websocket-version: 13\r\n"]
		assert_error([valid, "\r\n"], "upgrade")
		assert_error([valid, "upgrade: \r\n", "\r\n"], "upgrade")
		assert_error([valid, "upgrade: no", "\r\n"], "upgrade")
		assert_error([valid, "upgrade: test", "\r\n"], "upgrade")
		assert_error([valid, "upgrade: 323", "\r\n"], "upgrade")
	end

	test "error on missing or invalid connection" do
		valid = [request_line(), "Sec-WebsockeT-kEY: 239a9jk3 \r\n", "Host: www.x.com\r\n", "Sec-Websocket-version:  13\r\n", "upgrade: websocket\r\n"]
		assert_error([valid, "\r\n"], "connection")
		assert_error([valid, "connection: \r\n", "\r\n"], "connection")
		assert_error([valid, "connection: no", "\r\n"], "connection")
		assert_error([valid, "connection: test", "\r\n"], "connection")
		assert_error([valid, "connection: 323", "\r\n"], "connection")
	end

	test "successful" do
		assert_success(path: "/", key: "abc123", host: "test.com")
		assert_success(path: "?test-1", key: "1230919a", host: "test.net")
	end

	defp request_line() do
		:erlang.iolist_to_binary([
			Enum.random(["GET", "get", "Get", "gEt", "GEt", "gET"]),
			" ",
			Enum.random(["/", "/socket", "/ws", "/?over=9000"]),
			" ",
			Enum.random(["HTTP/1.1", "http/1.1", "Http/1.1", "hTTp/1.1"]),
			"\r\n"
		])
	end

	defp assert_error(buffer, error) do
		assert read(buffer) == :closed
		sent = GenTcpFake.sent()
		assert String.starts_with?(sent, "HTTP/1.1 400 Bad Request\r\n") == true
		assert sent =~ "Error: #{error}\r\n"
		assert sent =~ "Content-Length: 0\r\n"
		assert GenTcpFake.closed? == true
	end

	defp assert_success(opts) do
		req = [
			"GET #{opts[:path]} HTTP/1.1\r\n",
			"host: #{opts[:host]}\r\n",
			"Upgrade: WeBSocket\r\n",
			"Connection:   upgrADe \r\n",
			"sec-websocket-version: 13\r\n",
			"sec-websocket-key: #{opts[:key]}\r\n",
			"\r\n"
		]

		accept_key = :sha
		|> :crypto.hash([opts[:key], "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"])
		|> Base.encode64()

		{:ok, path, headers, _socket} = read(req)
		assert headers[:ip] == opts[:ip]
		assert path == opts[:path]

		ExWs.Handshake.accept(nil, headers)
		assert GenTcpFake.sent() == "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: #{accept_key}\r\n\r\n"
		assert GenTcpFake.closed? == false
	end

	defp assert_closed(buffer) do
		read(buffer)
		assert GenTcpFake.sent() == ""
		assert GenTcpFake.closed? == true
	end

	defp read(buffer) do
		GenTcpFake.reset(List.flatten(buffer))
		ExWs.Handshake.read(nil)
	end
end
