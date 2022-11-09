defmodule ExWs.Tests.ABHandler do
	use ExWs.Handler

	defp message(:bin, data, state) do
		write(ExWs.bin(data))
		state
	end

	defp message(:txt, data, state) do
		case String.valid?(:erlang.iolist_to_binary(data)) do
			true ->
				write(data)
				state
			false ->
				close("invalid utf8", 1007)
				state
		end
	end
end
