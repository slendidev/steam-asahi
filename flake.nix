{
  description = "Steam on NixOS Asahi Linux (Apple Silicon) via muvm + FEX-Emu";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "aarch64-linux";

      overlay = final: prev: {
        # --- libkrunfw 5.3.0 (kernel 6.12.76) ---
        libkrunfw = prev.libkrunfw.overrideAttrs (old: rec {
          version = "5.3.0";

          src = prev.fetchFromGitHub {
            owner = "containers";
            repo = "libkrunfw";
            tag = "v${version}";
            hash = "sha256-fhG/bP1HzmhyU2N+wnr1074WEGsD9RdTUUBhYUFpWlA=";
          };

          kernelSrc = prev.fetchurl {
            url = "mirror://kernel/linux/kernel/v6.x/linux-6.12.76.tar.xz";
            hash = "sha256-u7Q+g0xG5r1JpcKPIuZ5qTdENATh9lMgTUskkp862JY=";
          };
        });

        # --- libkrun 1.17.4 ---
        libkrun = prev.libkrun.overrideAttrs (old: rec {
          version = "1.17.4";

          src = prev.fetchFromGitHub {
            owner = "containers";
            repo = "libkrun";
            tag = "v${version}";
            hash = "sha256-Th4vCg3xHb6lbo26IDZES7tLOUAJTebQK2+h3xSYX7U=";
          };

          cargoDeps = prev.rustPlatform.fetchCargoVendor {
            inherit src;
            hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # TODO: compute
          };

          buildInputs = old.buildInputs ++ [ prev.libcap_ng ];
        });

        # --- muvm 0.5.1 ---
        muvm = prev.muvm.overrideAttrs (old: rec {
          version = "0.5.1";

          src = prev.fetchFromGitHub {
            owner = "AsahiLinux";
            repo = "muvm";
            tag = "muvm-${version}";
            hash = "sha256-eXsU2QRJ55gx5RhjT+m9F1KAFqGrd4WwnyR3eMpuIc4=";
          };

          cargoDeps = prev.rustPlatform.importCargoLock {
            lockFile = src + "/Cargo.lock";
          };
        });

        # --- FEX 2603 (with thunks) ---
        fex = prev.fex.overrideAttrs (old: {
          version = "2603";

          src = prev.fetchFromGitHub {
            owner = "FEX-Emu";
            repo = "FEX";
            tag = "FEX-2603";
            hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # TODO: compute

            leaveDotGit = true;
            postFetch = ''
              cd $out
              git reset

              # Fetch required submodules (same as nixpkgs 2511 + rpmalloc for 2603)
              git submodule update --init --depth 1 \
                External/Vulkan-Headers \
                External/drm-headers \
                External/jemalloc \
                External/jemalloc_glibc \
                External/rpmalloc \
                External/robin-map \
                External/vixl \
                Source/Common/cpp-optparse

              find . -name .git -print0 | xargs -0 rm -rf

              # Remove unnecessary directories
              rm -r \
                External/vixl/src/aarch32 \
                External/vixl/test
            '';
          };
        });
      };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ overlay ];
      };
    in
    {
      overlays.default = overlay;

      packages.${system} = {
        inherit (pkgs) libkrunfw libkrun muvm fex;
        steam-asahi = pkgs.callPackage ./pkgs/steam-asahi { };
        default = self.packages.${system}.steam-asahi;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.muvm
          pkgs.fex
          self.packages.${system}.steam-asahi
        ];

        shellHook = ''
          echo "asahi-steam dev shell"
          echo "  muvm $(muvm --version 2>&1 || echo 'available')"
          echo "  FEXBash available: $(which FEXBash 2>/dev/null && echo yes || echo no)"
          echo ""
          echo "Test commands:"
          echo "  muvm --interactive -- bash -c 'getconf PAGESIZE'   # should print 4096"
          echo "  muvm --interactive -- FEXBash -c 'uname -m'        # should print x86_64"
          echo "  steam-asahi                                         # launch Steam"
        '';
      };
    };
}
