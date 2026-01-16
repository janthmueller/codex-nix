{
  description = "Nix flake for OpenAI Codex CLI - AI coding assistant in your terminal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      channels = import ./channels.nix;
      overlay = final: prev: {
        codex = final.callPackage ./package.nix channels.latest;
        "codex-alpha" = final.callPackage ./package.nix channels.alpha;
        "codex-beta" = final.callPackage ./package.nix channels.beta;
        "codex-native" = final.callPackage ./package.nix channels.native;
      };
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ overlay ];
        };
      in
      {
        packages = {
          default = pkgs.codex;
          codex = pkgs.codex;
          alpha = pkgs."codex-alpha";
          beta = pkgs."codex-beta";
          native = pkgs."codex-native";
        };
        
        apps = {
          default = {
            type = "app";
            program = "${pkgs.codex}/bin/codex";
          };
          codex = {
            type = "app";
            program = "${pkgs.codex}/bin/codex";
          };
          alpha = {
            type = "app";
            program = "${pkgs."codex-alpha"}/bin/codex";
          };
          beta = {
            type = "app";
            program = "${pkgs."codex-beta"}/bin/codex";
          };
          native = {
            type = "app";
            program = "${pkgs."codex-native"}/bin/codex";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixpkgs-fmt
            nix-prefetch-git
            cachix
          ];
        };
      }) // {
        overlays.default = overlay;
      };
}
