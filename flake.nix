{
  description = "Jay's dotfiles – Nix Home Manager";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    minimal-emacs = {
      url = "github:jamescherti/minimal-emacs.d";
      flake = false;
    };
    paseo = {
      url = "github:getpaseo/paseo";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr = {
      url = "github:herdrdev/herdr/v0.8.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr-sessionizer = {
      url = "github:andrewchng/herdr-sessionizer/003785258f516b100370b3dd97688cf96c8679b5";
      flake = false;
    };
    herdr-last-workspace = {
      url = "github:third774/herdr-last-workspace/8b55ebf15deaa52b49ff1c2500aab0c19c729420";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      minimal-emacs,
      paseo,
      herdr,
      herdr-sessionizer,
      herdr-last-workspace,
      ...
    }:
    let
      # One configuration per system triple.
      # Username and home directory are detected at switch-time via
      # environment variables ($USER / $HOME) — see home.nix.
      mkHome =
        system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "drawio";
          };
          modules = [ ./home.nix ];
          extraSpecialArgs = {
            inherit
              minimal-emacs
              paseo
              herdr
              herdr-sessionizer
              herdr-last-workspace
              ;
          };
        };
    in
    {
      homeConfigurations = {
        "aarch64-linux" = mkHome "aarch64-linux";
        "x86_64-linux" = mkHome "x86_64-linux";
        "aarch64-darwin" = mkHome "aarch64-darwin";
      };
    };
}
