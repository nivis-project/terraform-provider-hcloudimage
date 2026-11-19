{
  description = "Terraform & OpenTofu provider for uploading raw disk images to Hetzner Cloud as reusable snapshots";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      # Plain-nix multi-system support — deliberately no flake-utils.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      linuxSystems = builtins.filter (s: nixpkgs.lib.hasSuffix "-linux" s) systems;

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true; # terraform is BUSL-licensed
        };

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (pkgsFor system));
      forLinuxSystems = f: nixpkgs.lib.genAttrs linuxSystems (system: f (pkgsFor system));

      # The provider package, defined once so packages/checks share it.
      providerFor =
        pkgs:
        pkgs.buildGoModule {
          pname = "terraform-provider-hcloudimage";
          version = "0.1.0-dev";
          src = ./.;

          # Bump whenever go.mod / go.sum change:
          #   set to pkgs.lib.fakeHash, run `nix build .#default`, copy the "got:" hash.
          vendorHash = "sha256-HxlNF8o+jzQlr0Lfv5udQUSG2p7HqDkvTmWaM+32Txw=";

          # Stamp the version into the binary the way goreleaser does (BRIEFING.md §10).
          ldflags = [
            "-s"
            "-w"
            "-X main.version=0.1.0-dev"
          ];

          # The package build only compiles the provider. Tests run in the
          # devShell / CI (unit) and, for the protocol layer, the hermetic
          # NixOS-VM check (milestone 05) — they need a terraform binary and
          # TF_ACC, which the buildGoModule sandbox deliberately lacks.
          doCheck = false;

          meta = {
            description = "Terraform & OpenTofu provider: upload raw disk images to Hetzner Cloud as snapshots";
            homepage = "https://github.com/nivis-project/terraform-provider-hcloudimage";
            license = pkgs.lib.licenses.mpl20;
            mainProgram = "terraform-provider-hcloudimage";
          };
        };

      mirrorFor = pkgs: import ./nix/provider-mirror.nix { inherit pkgs; provider = providerFor pkgs; };
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            go
            golangci-lint
            terraform
            opentofu
            terraform-plugin-docs
            goreleaser
            gnumake
            hcloud-upload-image
            hcloud # CLI for inspecting server types / locations and manual cleanup
          ];
        };
      });

      packages = forAllSystems (pkgs: {
        default = providerFor pkgs;
        # Filesystem-mirror layout so Nivis can consume the provider without a
        # public registry (BRIEFING.md §7). Documented consumption in milestone 09.
        provider-mirror = mirrorFor pkgs;

        # Reproducible Alpine acceptance fixtures (BRIEFING.md §8.3). test-image-x86
        # builds natively; test-image-arm targets aarch64 (built via a native
        # aarch64 runner, a configured remote builder, or binfmt/QEMU emulation —
        # see README). The arch is asserted in the derivation so the arm job never
        # silently uploads an x86 image.
        test-image-x86 = import ./nix/test-image.nix {
          inherit pkgs;
          arch = "x86_64";
          authorizedKey = ./test/fixtures/throwaway_ed25519.pub;
        };
        test-image-arm = import ./nix/test-image.nix {
          inherit pkgs;
          arch = "aarch64";
          authorizedKey = ./test/fixtures/throwaway_ed25519.pub;
        };
      });

      # Hermetic NixOS-VM lifecycle test — the PoC Definition-of-Done gate
      # (BRIEFING.md §8.2, §12). Linux-only (needs a VM builder). Picked up by
      # `nix flake check`.
      checks = forLinuxSystems (pkgs: {
        readme-header = pkgs.runCommand "readme-header" { } ''
          bash ${./scripts/check-readme-header.sh} ${./README.md} terraform-provider-hcloudimage "early but real"
          touch $out
        '';

        hermetic-e2e = import ./test/e2e/hermetic.nix {
          inherit pkgs;
          provider = providerFor pkgs;
          providerMirror = mirrorFor pkgs;
        };
      });

      # To be added per BRIEFING.md §7 as milestones progress:
      #   packages.test-image-x86   — Alpine amd64 fixture, .raw.xz, baked SSH key (milestone 07)
      #   packages.test-image-arm   — Alpine aarch64 fixture (milestone 07)
    };
}
