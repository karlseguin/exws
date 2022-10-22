defmodule ExWs.Reader do
	import Bitwise, only: [band: 2]

	alias __MODULE__
	alias ExWs.{Writer, Mask}

	@compile {:inline, atomize_op: 1}

	@error_invalid_op "invalid op" |> Writer.close(1002) |> Writer.to_binary()
	@error_control_len "large control" |> Writer.close(1002) |> Writer.to_binary()
	@error_control_fin "non-fin control" |> Writer.close(1002) |> Writer.to_binary()
	@error_preamble_unmasked "unmasked frame" |> Writer.close(1002) |> Writer.to_binary()
	@error_invalid_continuation "invalid continuation" |> Writer.close(1002) |> Writer.to_binary()

	@enforce_keys [:op, :fin, :len, :mask, :data, :chain]
	defstruct @enforce_keys

	defguard is_control(op) when op in [:close, :ping, :pong]

	def new() do
		%Reader{op: nil, fin: nil, len: nil, mask: {4, <<>>}, data: nil, chain: nil}
	end

	def received(data, frame), do: parse(data, frame, [])

	defp parse(<<>>, frame, []), do: {:ok, frame}
	defp parse(<<>>, frame, acc), do: {:ok, acc, frame}
	defp parse(<<b1, data::binary>>, %{op: nil} = frame, acc) do
		{op, fin} = case band(b1, 128) == 128 do
			true -> {b1 - 128, true}
			false -> {b1, false}
		end

		res = with {:ok, op} <- atomize_op(op) do
			has_chain? = frame.chain != nil
			is_control? = is_control(op)
			cond do
				op == :cont && !has_chain? -> {:close, @error_invalid_continuation}
				op != :cont && has_chain? && not is_control? -> {:close, @error_invalid_continuation}
				is_control? && !fin -> {:close, @error_control_fin}
				true -> parse(data, %Reader{frame | op: op, fin: fin}, acc)
			end
		end

		case {res, acc} do
			{{:close, _} = close, []} -> {:ok, close, frame}
			{{:close, _} = close, acc} -> {:ok, Enum.reverse([close | acc]), frame}
			{ok, _} -> ok
		end
	end

	defp parse(<<masked::1, len::7, data::binary>>, %{len: nil} = frame, acc) do
		cond do
			masked == 0 -> {:close, @error_preamble_unmasked}
			len > 125 && is_control(frame.op) -> {:close, @error_control_len}
			len == 127 -> parse(data, %Reader{frame | len: {8, <<>>}}, acc)
			len == 126 -> parse(data, %Reader{frame | len: {2, <<>>}}, acc)
			len == 0 -> parse(data, %Reader{frame | len: 0, data: <<>>}, acc)
			true -> parse(data, %Reader{frame | len: len, data: {len, []}}, acc)
		end
	end

	defp parse(data, %{len: {missing, known}} = frame, acc) do
		case data do
			<<len::bytes-size(missing), data::binary>> ->
				len = known <> len
				len = case byte_size(len) do
					2 -> <<len::big-16>> = len; len
					8 -> <<len::big-64>> = len; len
				end
				parse(data, %Reader{frame | len: len, data: {len, []}}, acc)
			_ -> {:ok, %Reader{frame | len: {missing - byte_size(data), known <> data}}}
		end
	end

	defp parse(data, %{mask: {missing, known}} = frame, acc) do
		case data do
			<<mask::bytes-size(missing), data::binary>> ->
				frame = %Reader{frame | mask: known <> mask}
				case frame.len == 0 do
					true -> finalize_frame(data, frame, acc)
					false -> parse(data, frame, acc)
				end
			_ -> {:ok, %Reader{frame | mask: {missing - byte_size(data), known <> data}}}
		end
	end

	defp parse(data, %{data: {missing, known}} = frame, acc) do
		case data do
			<<data::bytes-size(missing), extra::binary>> -> finalize_frame(extra, %Reader{frame | data: [known, data]}, acc)
			_ -> {:ok, %Reader{frame | data: {missing - byte_size(data), [known, data]}}}
		end
	end

	defp finalize_frame(extra, frame, acc) do
		data = Mask.apply(frame.mask, :erlang.iolist_to_binary(frame.data))
		{next_frame, acc} = continue(frame, data, acc)
		case {extra, acc} do
			{<<>>, []} -> {:ok, next_frame}
			{<<>>, acc} -> {:ok, Enum.reverse(acc), next_frame}
			{_, _} -> parse(extra, next_frame, acc)
		end
	end

	defp continue(%{fin: true, chain: nil} = frame, unmasked, acc) do
		acc = [{frame.op, unmasked} | acc]
		{new(), acc}
	end

	defp continue(%{fin: true, op: :cont, chain: {op, data}}, unmasked, acc) do
		acc = [{op, [data, unmasked]} | acc]
		{new(), acc}
	end

	defp continue(%{fin: true} = frame, unmasked, acc) do
		acc = [{frame.op, unmasked} | acc]
		{%Reader{new() | chain: frame.chain}, acc}
	end

	defp continue(%{fin: false} = frame, unmasked, acc) do
		chain = case frame.chain do
			nil -> {frame.op, [unmasked]}
			{op, data} -> {op, [data, unmasked]}
		end
		{%Reader{new() | chain: chain}, acc}
	end

	for {value, op} <- [cont: 0, txt: 1, bin: 2, close: 8, ping: 9, pong: 10] do
		defp atomize_op(unquote(op)), do: {:ok, unquote(value)}
	end
	defp atomize_op(_op), do: {:close, @error_invalid_op}
end
