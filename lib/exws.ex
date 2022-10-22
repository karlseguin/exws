defmodule ExWs do
	alias ExWs.Writer

	defdelegate txt(data), to: Writer
	defdelegate bin(data), to: Writer
	defdelegate to_binary(frame), to: Writer

	def invalid_handshake(err) do
		ExWs.Handshake.Errors.build(400, err)
	end

	def write(socket, {:framed, data}) do
		:gen_tcp.send(socket, data)
	end

	def write(socket, data) do
		write(socket, Writer.txt(data))
	end

	def ping(socket) do
		:gen_tcp.send(socket, Writer.ping())
	end

	def pong(socket, data) do
		:gen_tcp.send(socket, Writer.pong(data))
	end

	def close(socket, {:framed, data}) do
		:inet.setopts(socket, send_timeout: 1_000)
		:gen_tcp.send(socket, data)
		:gen_tcp.close(socket)
		:closed
	end

	def close(socket, message, code) do
		close(socket, Writer.close(message, code))
	end

	def close(socket) do
		close(socket, Writer.close(nil))
	end
end
