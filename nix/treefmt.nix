# treefmt-nix as a flake-parts module. This automatically wires `nix fmt`
# (the flake `formatter`) and a `treefmt` flake check. seihou-managed.
{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem = { ... }: {
    treefmt = {
      projectRootFile = "flake.nix";
      programs.nixpkgs-fmt.enable = true;
      programs.fourmolu.enable = true;
      # fourmolu can't auto-detect "manual" extensions, so they must be passed
      # explicitly. Override treefmt-nix's default set: this project uses `pattern`
      # as a lens identifier (so PatternSynonyms must NOT be on) and relies on CPP.
      programs.fourmolu.ghcOpts = [
        "BangPatterns"
        "TypeApplications"
        "CPP"
      ];
      programs.cabal-fmt.enable = true;
    };
  };
}
