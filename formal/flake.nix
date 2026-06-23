{
  description = "Formal proofs of contracts-library specs (Lean 4 + Lean-Blaster + Z3)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Z3 pinned to 4.15.2, the version Lean-Blaster targets. We override the
        # nixpkgs derivation's source so we keep its (cmake) build recipe but get
        # the exact upstream tag.
        z3 = pkgs.z3.overrideAttrs (old: rec {
          version = "4.15.2";
          src = pkgs.fetchFromGitHub {
            owner = "Z3Prover";
            repo = "z3";
            rev = "z3-${version}";
            hash = "sha256-hUGZdr0VPxZ0mEUpcck1AC0MpyZMjiMw/kK8WX7t0xU=";
          };
        });
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            # Manages the Lean toolchain. On first `lake`/`lean` invocation elan
            # reads ./lean-toolchain (leanprover/lean4:v4.24.0) and fetches it.
            pkgs.elan
            z3
            pkgs.gawk   # `just verify` pipes lake output through annotate-blaster-logs.awk
          ];

          shellHook = ''
            echo "formal/ — Lean 4 + Lean-Blaster + Z3 dev shell"
            echo "  z3:   $(z3 --version 2>/dev/null || echo missing)"
            echo "  elan: $(elan --version 2>/dev/null || echo missing)  (Lean pinned in ./lean-toolchain)"
            echo
            echo "  build the proofs:  lake update && lake build"
          '';
        };

        # Exposed so CI or `nix build .#z3` can reuse the exact pin.
        packages.z3 = z3;
      });
}
