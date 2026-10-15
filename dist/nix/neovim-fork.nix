{ stdenv, lib, fetchurl, autoPatchelfHook }:

# Neovim fork (traditional tarball from GitHub Release).
# Generated + verified by CI (.github/workflows/fork-tarball.yml):
#   version/url/hash are filled in by CI on every push to release_fork and
#   uploaded as release asset `neovim-fork.nix`. This file in dotfiles is a
#   copy fetched by pkgs/update-fork-tarballs.sh — do not edit hash by hand.
stdenv.mkDerivation rec {
  pname = "neovim-fork";
  version = "0.0.0-unset";

  src = fetchurl {
    url = "https://github.com/WantenMN/neovim/releases/download/fork-linux-x86_64/neovim-linux-x86_64.tar.gz";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  # Tarball has multiple top-level entries (bin/ lib/ share/); unpack in place.
  sourceRoot = ".";

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  # Tarball top level is bin/ lib/ share/ (contents of stage/usr, no usr/ wrapper).
  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r bin lib share $out/

    # Upstream renamed runtime/nvim.desktop -> org.neovim.nvim.desktop;
    # keep the old name as a symlink for wrappers expecting it.
    if [ -f $out/share/applications/org.neovim.nvim.desktop ] && [ ! -e $out/share/applications/nvim.desktop ]; then
      ln -s org.neovim.nvim.desktop $out/share/applications/nvim.desktop
    fi

    runHook postInstall
  '';

  # nvim is mostly statically bundled (libuv/luajit/tree-sitter built in);
  # autoPatchelf only rewrites libc + parser .so NEEDED entries.
  meta = {
    description = "Neovim fork (prebuilt tarball)";
    homepage = "https://github.com/WantenMN/neovim";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "nvim";
  };
}
