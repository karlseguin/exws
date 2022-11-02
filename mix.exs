defmodule ExWs.Mixfile do
	use Mix.Project

	def project do
		[
			app: :exws,
			deps: deps(),
			version: "0.0.2",
			elixir: "~> 1.14",
			elixirc_paths: paths(Mix.env),
			build_embedded: Mix.env == :prod,
			start_permanent: Mix.env == :prod,
			compilers: Mix.compilers,
			description: "Elixir Websocket Server - Kitchen Sink Not Included",
			package: [
				licenses: ["MIT"],
				links: %{
					"git" => "https://github.com/karlseguin/exws"
				},
				maintainers: ["Karl Seguin"]
			]
		]
	end

	defp paths(:ab), do: paths(:test)
	defp paths(:test), do: paths(:prod) ++ ["test/support"]
	defp paths(_), do: ["lib"]

	def application do
		[
			extra_applications: [:crypto, :logger]
		]
	end

	defp deps do
		[
			{:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
			{:jiffy, git: "https://github.com/karlseguin/jiffy", only: [:test, :ab]}
		]
	end
end
