{
  description = "Neovim fork (release_fork -> wanten cachix)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      # Fork package: nixpkgs neovim-unwrapped recipe, source replaced with
      # this tree (i.e. master + local fixes). Wrapped with nixpkgs
      # wrapNeovim (see pkgs/applications/editors/neovim/wrapper.nix),
      # built and pushed to Cachix by CI.
      packages = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          neovim-fork-unwrapped = pkgs.neovim-unwrapped.overrideAttrs (old: {
            # Must match NVIM_VERSION_* in CMakeLists.txt. Bump when upstream
            # bumps (see FORK.md). Keep stable (no per-commit suffix) so
            # treesitter grammars (versioned "neovim-${version}") stay cached;
            # src change alone still rebuilds nvim itself.
            version = "0.13.0-dev";
            # Use fileset source (not `self`): excludes fork-only files so
            # CI (local checkout) and consumers (github tarball) hash the
            # same src and hit the same Cachix path. Otherwise the two
            # fetchers produce different `self` store paths for the same
            # commit and every system build recompiles locally.
            # niri does the same (allowlist); here a denylist is safer for
            # rebases (new upstream files are included automatically).
            src = nixpkgs.lib.fileset.toSource {
              root = ./.;
              fileset = nixpkgs.lib.fileset.difference ./. (
                nixpkgs.lib.fileset.unions [
                  ./flake.nix
                  ./flake.lock
                  ./FORK.md
                  ./sync-upstream.sh
                  # Upstream .gitattributes has `.github/ export-ignore`, so
                  # github tarballs (flake-input consumption) lack .github
                  # while local checkouts have it. maybeMissing keeps both
                  # sides hashing the same src.
                  (nixpkgs.lib.fileset.maybeMissing ./.github)
                ]
              );
            };
            # Upstream renamed runtime/nvim.desktop -> org.neovim.nvim.desktop
            # after 0.12.5, but nixpkgs wrapper.nix still expects the old path
            # (rm + substitute nvim.desktop). Provide a compat symlink so the
            # unmodified wrapper keeps working on master.
            postInstall = (old.postInstall or "") + ''
              if [ -f $out/share/applications/org.neovim.nvim.desktop ] && [ ! -e $out/share/applications/nvim.desktop ]; then
                ln -s org.neovim.nvim.desktop $out/share/applications/nvim.desktop
              fi
            '';
          });
          # NOTE: pkgs.wrapNeovim = legacy wrapper -> wrapNeovimUnstable
          # (pkgs/applications/editors/neovim/wrapper.nix). No args = plain
          # nvim, same CLI as unwrapped plus desktop-file handling above.
          neovim-fork = pkgs.wrapNeovim neovim-fork-unwrapped { };
        in
        {
          inherit neovim-fork;
          default = neovim-fork;
        }
      );

      devShells = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [ pkgs.neovim-unwrapped ];
            shellHook = ''
              export VIMRUNTIME=$PWD/runtime
              echo "Neovim dev shell (nix develop, no nix-store rebuild)."
              echo "  make CMAKE_BUILD_TYPE=RelWithDebInfo"
              echo "  ./build/bin/nvim   # run without install"
            '';
          };
        }
      );
    };
}
