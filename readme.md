Dependency-Free, Compliant Websocket Server written in Elixir. 

Kitchen sink *not* included. Every mandatory [Autobahn Testsuite](https://github.com/crossbario/autobahn-testsuite) case is passing. (Three fragmented UTF-8 are flagged as non-strict and as compression is not implemented, these are all flagged as "Unimplemented")

If you're looking for a channel/room implementation, check out [ExWsChannels](https://github.com/karlseguin/exws_channels).

## Example
```elixir
defmodule YourApp.YourWSHandler do
  # This is the only function you HAVE to define.
  # Note that WebSocket messages are just bytes that could represent
  # anything. ExWs exposes these bytes as-is (as an iodata). In most
  # cases, you'll probably want to decode that using JSON and process
  # the resulting payload, but exposing the raw bytes allows for 
  # a lot more possibilities.
  def message(data, state) do
    # be careful, data is an iodata
    case Jason.decode(data) do
      {:ok, data} -> process(data)
      _ -> close(3000, "invalid payload")
    end
  end

  defp process(%{"join" => channel}) do
    #...
  end
end
```

## Usage

Include the dependency in your project:

```
{:exms, "~> 0.0.1"}
```

Define your handler:
```elixir
defmodule YourApp.YourWSHandler do
  use ExWs.Handler

  def message(_data, state) do
    # do something with data
    state
  end
end
```

And start the server in your supervisor tree:
```elixir
children = [
  # ...
  {ExWs.Supervisor, [port: 4545, handler: YourApp.YourWSHandler]}
]
```

## Writing
From within your handler, you can use the `write/1` function to
send a message to the user:

```elixir
def message(data, state) do
  # data is an iolist
  write(data) # echo the message back to the user
  state
end
```

## Handshake
The `handshake/3` callback lets you handle the initial handshake:

```elixir
# this is the default implementation
def handshake(_path, _headers, state) do
  {:ok, state}
end
```

Where `path` is the requested URL path as a string, and `headers` is a map with lowercase string keys.

If you want to reject the handshake, say because the path/headers does not contain the correct authentication, return a `{:close, ExWs.invalid_handshake/1}`:

```elixir
def handshake(_path, headers, state) do
  case lookup_one_time_token(headers["token"]) do
    {:ok, user_id} -> {:ok, %{user_id: user_id}} # set a new state
    _ -> {:close, ExWs.invalid_handshake("invalid_token")}
  end
end
```

Note that the value given to `ExWs.invalid_handshale/1` (in the above case, we're talking about "invalid_token") is placed in the `Error` header of the handshake response (for troubleshooting purpose)


### init
You can set the initial state by providing an `init/0` callback:

```elixir
# this is the default implementation
def init(), do: nil
````

### Closed
The `closed/2` callback is called whenever the socket is closed:

```elixir
# default closed/2 implementation
defp closed(_reason, state) do
  shutdown()
  state
end
```

If you overwrite `closed/2`, you almost certainly want to call `shutdown/0` (it both closes the socket and shuts down the underlying GenServer).

## Handler Functions
Within your handler, the following functions are available:

- `ping/0` send a ping message to the client
- `write/1` writes the message to the client
- `close/0` close the connection
- `close2/` close the connection specifying a `code` and `message`. As per the specs, your `code` should be 3000-4999. Your message must be < 123 bytes.
- `get_socket/0` gets the underlying socket

Note that `get_socket/0` will return the socket during `init/0` and `closed/2` (but the socket can be closed by the other side at any point).

Note that if you call `close/0` directly, the `closed/2` callback will be executed.

## Write Optimizations
All WebSocket messages are framed and there's some overhead in creating this framing. When you call `write/1` with a binary value, the handler will frame your payload and write the framed message to the socket.

For static messages, you can opt to pre-frame the message using the `ExWs.bin/1` and `ExWs.txt/1` functions. `write/1` will detect these pre-framed messages and send them directly as-is.

```elixir
defmodule YourApp.YourWSHandler do
  use ExWs.Handler

  @message_over_9000 ExWs.txt(" 9000!!")
  def message("it's over", state) do
    write(@message_over_9000)
    state
  end
end
```

## txt vs bin
WebSocket has a separate message type for binary data and text data. Implementations must reject any message declared as txt which is not valid UTF8. 

This library does not do this validation. The `message/2` callback receives both text and binary messages.

If you want to differentiate between the two, implement `message/3` instead of `message/2`:

```elixir
def message(op, data, state) do
  # op will be :txt or :bin
end
```

The default `write/1` function uses the text type. You can override `write/1` to change this behavior:

```elixir
defp write(data) do
  ExWs.write(get_socket(), ExWs.bin(data))
end
```

Or you can do it on a case-by-case basis:
```elixir
write(ExWs.bin(some_data))

write(data) 
# as as
write(ExBin.txt(data))
```

## Direct Socket Usage
For performance reason, you may want to write directly to the socket, without going through the handler. For example, you might implement room/channel logic by storing the socket directly into the ETS table (writing to sockets from concurrent elixir processes is fine).

As we already saw, the `get_socket/0` helper will return the socket. But you cannot write to the socket directly using `gen_tcp.send/2` since weboscket messages must be framed.

You have two options, either use the `ExWs.bin/1` and `ExWs.txt/1` helpers to frame data:

```elixir
:gen_tcp.send(socket, ExWs.txt("leto atreides"))
```

Or use the `ExWs.write/2` helper:

```elixir
ExWs.write(socket, "leto atreides")
```

Note that `ExWs` also exposes `ping/1` and `close/1`.
