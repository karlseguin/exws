defmodule ExWs.Tests.Integration do
	use ExWs.Tests
	alias ExWs.Tests.WS

	setup_all do
		ExWs.GenTcpFake.real()
	end

	setup do
		:ets.delete_all_objects(:integration_tests)
		:ets.insert(:integration_tests, {:test_pid, self()})
		:ok
	end

	test "handshake timeout" do
		WS.connect(4545)
		receive do
			{:closed, reason} -> assert reason == :reject_handshake
		end
		:timer.sleep(50)
		assert Process.alive?(get_handler()) == false
	end

	test "handshake error" do
		ws = WS.handshake(4545, "/fail")
		assert ws.status == 400
		assert ws.headers["error"] == "handshake_fail"
		assert :gen_tcp.recv(ws.socket, 0, 100) == {:error, :closed}
		:timer.sleep(50)
		assert Process.alive?(get_handler()) == false
	end

	test "client disconnect" do
		WS.kill(WS.handshake(4545, "/"))
		receive do
			{:closed, reason} -> assert reason == :tcp_closed
		end
		:timer.sleep(50)
		assert Process.alive?(get_handler()) == false
	end

	defp get_handler() do
		case :ets.lookup(:integration_tests, :handler_pid) do
			[{:handler_pid, value}] -> value
			_ -> nil
		end
	end
end

defmodule ExWs.Tests.Integration.Handler do
	use ExWs.Handler,
		handshake_timeout: 50

	@handshake_fail ExWs.invalid_handshake("handshake_fail")

	def init() do
		:ets.insert(:integration_tests, {:handler_pid, self()})
		%{}
	end

	def handshake("/fail", _headers, _state) do
		{:close, @handshake_fail}
	end

	def handshake(_path, _headers, state) do
		{:ok, state}
	end

	def closed(reason, state) do
		if Map.get(state, :no_close) == nil || reason != :tcp_closed do
			send_to_test({:closed, reason})
			shutdown()
		end
		state
	end

	def message(data, state) do
		data = :jiffy.decode(data)
		handle_message(data.action, data, state)
	end

	defp handle_message("no_close", _, state) do
		Map.put(state, :no_close, true)
	end

	defp send_to_test(message) do
		case :ets.lookup(:integration_tests, :test_pid) do
			[{:test_pid, pid}] -> send(pid, message)
			_ -> :ok
		end
	end
end
