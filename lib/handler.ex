defmodule ExWs.Handler do
	defmacro __using__(_opts) do
		quote location: :keep do
			use GenServer

			alias ExWs.{Handshake, Writer}
			@compile {:inline, get_socket: 0, get_reader: 0, put_reader: 1}

			@ws_empty_close <<>> |> Writer.close(1000) |> Writer.to_binary()
			@ws_normal_close "Normal Closure" |> Writer.close(1000) |> Writer.to_binary()
			@ws_invalid_close <<>> |> Writer.close(1002) |> Writer.to_binary()

			def init({socket, reader}) do
				put_socket(socket)
				put_reader(reader)
				{:ok, init()}
			end

			defp init(), do: nil
			defp handshake(_path, _header, state), do: {:ok, state}
			defp closed(_reason, state) do
				shutdown()
				state
			end

			# Most handlers probably won't care about :bin vs :txt message
			# ops, so by default we discard it. If a handler does care about
			# the specific op, it can implement its own message/3
			defp message(_op, data, state), do: message(data, state)
			defoverridable [init: 0, handshake: 3, closed: 2, message: 3]

			def handle_cast(:ready, state) do
				socket = get_socket()
				with {:ok, path, headers, socket} <- Handshake.read(socket),
				     {:ok, state} <- handshake(path, headers, state)
				do
					:inet.setopts(socket, packet: :raw, active: true)
					Handshake.accept(socket, headers)
					{:noreply, state}
				else
					:closed -> {:noreply, closed(:reject_handshake, state)}
					{:close, error} ->
						Handshake.reject(socket, error)
						{:noreply, closed(:reject_handshake, state)}
				end
			end

			def handle_cast(:shutdown, state), do: {:stop, :normal, state}

			def handle_info({:tcp, socket, data}, state) do
				message =
					case ExWs.Reader.received(data, get_reader()) do
						{:ok, reader} -> put_reader(reader); :ok
						{:ok, messages, reader} -> put_reader(reader); {:ok, messages}
					end


				state = case message do
					:ok -> state
					{:ok, {op, message}} -> message_received(op, message, state)
					{:ok, messages} ->
						Enum.reduce(messages, state, fn {op, message}, state ->
							message_received(op, message, state)
						end)
					{:close, reason} -> closed(reason, state)
				end
				{:noreply, state}
			end

			def handle_info({:tcp_closed, _socket}, state) do
				{:noreply, closed(:tcp_closed, state)}
			end

			def handle_info({:tcp_error, socket, _reason}, state) do
				:gen_tcp.close(socket)
				{:noreply, closed(:tcp_error, state)}
			end

			defp message_received(op, data, state) when op in [:bin, :txt] do
				message(op, data, state)
			end

			defp message_received(:close, data, state) do
				handle_close(data, :client, state)
			end

			defp message_received(:ping, data, state) do
				ExWs.pong(get_socket(), data)
				state
			end

			defp message_received(:pong, _data, state), do: state

			# This is typically called when our Reader gets an invalid message.
			# For example, if we get an invalid op code, the close message is
			# framed at compile-time (for efficiency) and we end up here
			defp handle_close({:framed, data} = frame, _reason, state) do
				ExWs.close(get_socket(), frame)
				closed(:protocol, state)
			end

			defp handle_close(data, reason, state) do
				data = case :erlang.iolist_to_binary(data || "") do
					<<code::big-16, message::binary>> ->
						cond do
							code == 1001 -> @ws_normal_close
							code < 1000 || code in [1004, 1005, 1006] || (code > 1013 && code < 3000) -> @ws_invalid_close
							String.valid?(message) -> Writer.close_echo(data)
							true -> @ws_invalid_close
						end
					<<>> -> @ws_normal_close
					_ -> @ws_invalid_close
				end
				ExWs.close(get_socket(), data) # echo this back to the client, as per the spec
				closed(reason, state)
			end

			defp ping(), do: ExWs.ping(get_socket())
			defp close(), do: ExWs.close(get_socket())
			defp close(message, code), do: ExWs.close(get_socket(), message, code)
			defp write(data), do: ExWs.write(get_socket(), data)
			defoverridable [write: 1] # incase you want the default to be bin

			defp shutdown() do
				:gen_tcp.close(get_socket())
				GenServer.cast(self(), :shutdown)
			end

			defp get_socket(), do: Process.get(:socket)
			defp put_socket(socket), do: Process.put(:socket, socket)

			defp get_reader(), do: Process.get(:reader)
			defp put_reader(reader), do: Process.put(:reader, reader)
		end
	end
end
