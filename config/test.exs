import Config

config :exws,
	port: 4545,
	handler: ExWs.Tests.Integration.Handler

if System.get_env("AB") == "1" do
	import_config "ab.exs"
end
