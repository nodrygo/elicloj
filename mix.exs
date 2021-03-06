defmodule Elicloj.Mixfile do
  use Mix.Project

  def project do
    [ app: :elicloj,
      version: "0.0.2",
      elixir: "> 0.11.0",
      elixirc_paths: ["lib","demo"],      
      deps: deps ]
  end


  # Returns the list of dependencies in the format:
  # { :foobar, "~> 0.1", git: "https://github.com/elixir-lang/foobar.git" }
  defp deps do
    [ { :bencodelix, github: "nodrygo/bencodelix" }
    ]
  end
  
end
