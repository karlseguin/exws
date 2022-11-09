defmodule ExWs.Writer do
	import Bitwise, only: [bor: 2]

	@op_txt bor(128, 1)
	@op_bin bor(128, 2)
	@op_ping bor(128, 9)
	@op_pong bor(128, 10)
	@op_close bor(128, 8)

	@empty_ping <<@op_ping, 0>>
	@empty_pong <<@op_pong, 0>>
	@empty_close <<@op_close, 0>>

	def ping(), do: @empty_ping

	def pong(<<>>), do: @empty_pong
	def pong(payload), do: [@op_pong, encode_length(payload), payload]

	def close({:framed, _} = framed), do: framed
	def close(payload) when payload in [nil, [], <<>>] do
		{:framed, @empty_close}
	end

	def close(payload, code) when byte_size(payload) < 123 do
		{:framed, [@op_close, encode_length(payload, 2), <<code::big-16>>, payload]}
	end

	def close_echo(payload) do
		{:framed, [@op_close, encode_length(payload), payload]}
	end

	def to_binary({:framed, data}), do: {:framed, :erlang.iolist_to_binary(data)}

	def bin({:framed, _} = framed), do: framed
	def bin(payload), do: {:framed, [@op_bin, encode_length(payload), payload]}

	def txt({:framed, _} = framed), do: framed
	def txt(payload), do: {:framed, [@op_txt, encode_length(payload), payload]}

	defp encode_length(data, add \\ 0)
	defp encode_length(nil, 0), do: 0
	defp encode_length(data, add) do
		len = :erlang.iolist_size(data) + add
		cond do
			len < 126 -> len
			len < 65_536 -> <<126, len::big-16>>
			true -> <<127, len::big-64>>
		end
	end
end
