defmodule ExWs.Mask do
	import Bitwise, only: [bxor: 2]

	def apply(mask, data) do
		l = byte_size(data)
		mask = cond do
			l < 5 -> mask
			l < 9 -> <<mask::binary, mask::binary>>
			l < 13 -> <<mask::binary, mask::binary, mask::binary>>
			l < 17 -> <<mask::binary, mask::binary, mask::binary, mask::binary>>
			l < 21 -> <<mask::binary, mask::binary, mask::binary, mask::binary, mask::binary>>
			l < 25 -> <<mask::binary, mask::binary, mask::binary, mask::binary, mask::binary, mask::binary>>
			l < 29 -> <<mask::binary, mask::binary, mask::binary, mask::binary, mask::binary, mask::binary, mask::binary>>
			true -> <<mask::binary, mask::binary, mask::binary, mask::binary, mask::binary, mask::binary, mask::binary, mask::binary>>
		end
		unmask(mask, data, [])
	end

	defp unmask(_, <<>>, unmasked), do: unmasked

	defp unmask(<<mask::256>> = m, <<word::256, data::binary>>, unmasked) do
		unmask(m, data, [unmasked, <<bxor(word, mask)::256>>])
	end

	for i <- (31..1) do
		size = 8 * i
		defp unmask(<<mask::unquote(size), _::binary>>, <<word::unquote(size)>>, unmasked) do
			[unmasked, <<bxor(word, mask)::unquote(size)>>]
		end
	end
end
