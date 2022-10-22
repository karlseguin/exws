defmodule ExWs.Tests.Frame do
	use ExWs.Tests
	import Bitwise, only: [bor: 2]

	alias ExWs.Mask
	alias ExWs.Reader

	test "error on unknown op" do
		assert_error(received(build(op: 20)), 1002, "invalid op")
	end

	test "error if unmasked" do
		assert_error(received(build(mask: false)), 1002, "unmasked frame")
	end

	test "error on large control" do
		body = String.duplicate("!", 126)
		for op <- [:close, :ping, :pong] do
			assert_error(received(build(op: op, data: body)), 1002, "large control")
		end
	end

	test "error on unexpected cont" do
		assert_error(received(build(op: :cont)), 1002, "invalid continuation")
	end

	test "error on expected but missing cont" do
		{:ok, reader} = received(build(fin: false))
		assert_error(received(build(op: :txt), reader), 1002, "invalid continuation")
	end

	test "parses a full bodyless" do
		data = build(fin: true, op: :txt)
		assert {:ok, [{:txt, <<>>}], reader} = received(data)
		assert_new(reader)
	end

	test "parses a full small-body" do
		data = build(fin: true, op: :bin, data: "hello")
		assert {:ok, [{:bin, "hello"}], reader} = received(data)
		assert_new(reader)
	end

	test "parses a full medium-body" do
		body = String.duplicate("a", 200)
		data = build(fin: true, op: :txt, data: body)
		assert {:ok, [{:txt, ^body}], reader} = received(data)
		assert_new(reader)
	end

	test "parses a full large-body" do
		body = String.duplicate("b", 65537)
		data = build(fin: true, op: :txt, data: body)
		assert {:ok, [{:txt, ^body}], reader} = received(data)
		assert_new(reader)
	end

	test "parses two full bodyless" do
		data = build(fin: true, op: :bin) <> build(fin: true, op: :txt)
		assert {:ok, [{:bin, <<>>}, {:txt, <<>>}], reader} = received(data)
		assert_new(reader)
	end

	test "parses two full small-body" do
		data = build(fin: true, op: :txt, data: "over") <> build(fin: true, op: :txt, data: "9000!")
		assert {:ok, [{:txt, "over"}, {:txt, "9000!"}], reader} = received(data)
		assert_new(reader)
	end

	test "parses two full med-body" do
		b1 = String.duplicate("c", 200)
		b2 = String.duplicate("d", 9001)
		data = build(fin: true, op: :txt, data: b1) <> build(fin: true, op: :txt, data: b2)
		assert {:ok, [{:txt, ^b1}, {:txt, ^b2}], reader} = received(data)
		assert_new(reader)
	end

	test "parses two full large-body" do
		b1 = String.duplicate("e", 65537)
		b2 = String.duplicate("f", 75537)
		data = build(fin: true, op: :bin, data: b1) <> build(fin: true, op: :bin, data: b2)
		assert {:ok, [{:bin, ^b1}, {:bin, ^b2}], reader} = received(data)
		assert_new(reader)
	end

	test "parses ws fragmented message" do
		{:ok, reader} = received(build(fin: false, data: "over "))
		assert {:ok, [{:bin, "over 9000!!!"}], reader} = received(build(op: :cont, data: "9000!!!"), reader)
		assert_new(reader)
	end

	test "parses ws frabingmented message with interleaved control" do
		{:ok, reader} = received(build(fin: false, data: "over "))
		{:ok, [{:ping, "ping?"}], reader} = received(build(op: :ping, data: "ping?"), reader)
		{:ok, reader} = received(build(fin: false, op: :cont, data: "9000"), reader)
		assert {:ok, [{:bin, "over 9000!"}], reader} = received(build(op: :cont, data: "!"), reader)
		assert_new(reader)
	end

	test "parses a data-less message with tcp fragmentation" do
		<<op::bytes-size(1), data::binary>> = build(data: "leto")
		assert_fragment([op, data], "leto")
	end

	test "parses a tcp fragmented frame" do
		data = :erlang.binary_to_list(build(data: "leto"))
		Enum.reduce(data, Reader.new(), fn c, reader ->
			case received(<<c>>, reader) do
				{:ok, reader} -> reader
				{:ok, [{:bin, "leto"}], reader} -> assert_new(reader); :invalid_acc
			end
		end)
	end

	test "parses a tcp fragmented medium sized frame" do
		body = String.duplicate("a", 150)
		data = :erlang.binary_to_list(build(data: body))
		Enum.reduce(data, Reader.new(), fn c, reader ->
			case received(<<c>>, reader) do
				{:ok, reader} -> reader
				{:ok, [{:bin, ^body}], reader} -> assert_new(reader); :invalid_acc
			end
		end)
	end

	test "parses a tcp fragmented large sized frame" do
		body = String.duplicate("a", 17828)
		data = :erlang.binary_to_list(build(data: body))
		Enum.reduce(data, Reader.new(), fn c, reader ->
			case received(<<c>>, reader) do
				{:ok, reader} -> reader
				{:ok, [{:bin, ^body}], reader} -> assert_new(reader); :invalid_acc
			end
		end)
	end

	defp assert_fragment(fragments, expected_data) do
		Enum.reduce(fragments, Reader.new(), fn fragment, reader ->
			case received(fragment, reader) do
				{:ok, reader} -> reader
				{:ok, [{:bin, actual}], reader} ->
					assert expected_data == actual
					reader
			end
		end)
	end

	defp assert_error({:ok, {:close, {:framed, data}}, _frame}, expected_code, expected_message) do
		# 136 fin | close  (128 | 8)
		<<136, len::8, ^expected_code::big-16, ^expected_message::binary>> = data
		# close message is ALWAYS < 126 and the mask flag is off (server messages are never masked)
		assert len < 126
	end

	defp assert_new(reader) do
		assert reader.op == nil
		assert reader.fin == nil
		assert reader.len == nil
		assert reader.data == nil
		assert reader.chain == nil
		assert reader.mask == {4, <<>>}
	end

	defp received(data) do
		received(data, Reader.new())
	end

	defp received(data, reader) do
		case Reader.received(data, reader) do
			{:ok, messages, reader} when is_list(messages) ->
				messages = Enum.map(messages, fn {k, v} ->
					{k, :erlang.iolist_to_binary(v)}
				end)
				{:ok, messages, reader}
			other -> other
		end
	end

	defp build(opts) do
		op = case opts[:op] do
			:cont -> 0
			:txt -> 1
			:close -> 8
			:ping -> 9
			:pong -> 10
			op when is_integer(op) -> op
			_ -> 2
		end

		b1 = case opts[:fin] do
			false -> <<op>>
			_ -> <<bor(op, 128)>>
		end

		mask = case opts[:mask] do
			nil -> <<:rand.uniform(4294967295)::big-32>> # almost all test want a mask, so make this the default
			false -> <<>>
		end

		data = opts[:data] || <<>>
		len = opts[:len] || byte_size(data)

		mask_flag = case byte_size(mask) == 0 do
			true -> 0
			false -> 128
		end

		len = cond do
			len < 126 -> <<bor(len, mask_flag)>>
			len < 65536 -> <<bor(126, mask_flag), len::big-16>>
			true -> <<bor(127, mask_flag), len::big-64>>
		end

		data = case mask do
			<<>> -> data
			mask -> :erlang.iolist_to_binary(Mask.apply(mask, data))
		end

		b1 <> len <> mask <> data
	end
end
