let

    # Some constant configuration that's factored separately.
    #
    config = import ./config.nix;

    # For reproducibility we'll use this project's pinned Nixpkgs instead of
    # `(import <nixpkgs> {})`.  This way we get a specific version of Nixpkgs
    # instead of a version that happens to be in the environment's `NIX_PATH`.
    #
    sources = import ../nix-haskell-hls/nix/sources;
    # nixpkgs = (import sources.nixpkgs-unstable) {
    nixpkgs = (import sources.nixpkgs-stable) {
        # We don't want user configuration affecting this build.  This is
        # recommended boilerplate when importing Nixpkgs.
        config   = { allowBroken = true;};  # to avoid picking up ~/.config/nixpkgs/config.nix
        overlays = [];  # to avoid picking up ~/.config/nixpkgs/overlays
    };

    # obeliskSrc = import .obelisk/impl/thunk.nix;
    obeliskSrc = ./.obelisk/impl;
    obeliskProject = import ./default.nix {};

    # This is the build of HLS for this project.
    #
    hls = import ../nix-haskell-hls/. {
        ghcVersion = config.ghcVersion;
        hlsUnstable   = config.hlsUnstable;
    };

    # This function helps filter source to just what's needed.  This way, any
    # intermediate files created while developing don't affect Nix hash
    # calculations, which could result in cache misses against /nix/store.
    #
    cleaned = path: nixpkgs.lib.sourceFilesBySuffices path
        [".hs" ".lhs" ".cabal"];

    # `packageSourceOverrides` is not documented widely.  The best documentation
    # is in Nixpkgs' source.  This call helps us map our plain Cabal projects to
    # an attribute name.  We end up with a function we can use to extend the
    # Nixpkgs build of Haskell packages with the build of our project.  This
    # allows our build to reference dependencies already in Nixpkgs.
    #
    # Note that for each package in our Cabal project, we need an entry.  And
    # the attribute names need to match the package names referenced in the
    # Cabal file.
    #
    # Also, note that this function is aware of a very large percentange of
    # non-Haskell dependencies needed by Hackage packages.  If you have a
    # Hackage dependency in your Cabal file that requires a non-Haskell
    # dependency (as is the case with example-haskell-app pulling text-icu),
    # then packageSourceOverrides should pull in what's needed automatically.
    #
    overrides = nixpkgs.lib.composeExtensions (nixpkgs.haskell.lib.packageSourceOverrides {
        common = cleaned ./common;
        obelisk-route = obeliskSrc + "/lib/route";
        obelisk-executable-config-lookup = obeliskSrc + "/lib/executable-config/lookup";
        tabulation = obeliskSrc + "/lib/tabulation";
        # example-haskell-lib = cleaned ./library;
        frontend = cleaned ./frontend;
        obelisk-frontend = obeliskSrc + "/lib/frontend";
        obelisk-generated-static = obeliskSrc + "/lib/frontend";
        obelisk-executable-config-inject = obeliskSrc + "/lib/executable-config/inject";
        obelisk-asset-manifest = obeliskSrc + "/lib/asset/manifest";
    }) (self: super: {
        reflex-dom = nixpkgs.haskell.lib.addBuildDepend (nixpkgs.haskell.lib.enableCabalFlag super.reflex-dom "use-warp") self.jsaddle-warp;
        jsaddle-webkit2gtk = null;
        monoidal-containers = nixpkgs.haskell.lib.doJailbreak super.monoidal-containers;
        obelisk-generated-static = nixpkgs.haskell.lib.dontHaddock (self.callCabal2nix "obelisk-generated-static" obeliskProject.passthru.processedStatic.haskellManifest {});
    });

    # Here we extend Nixpkgs' build of Haskell packages for a specific version
    # of GHC.  The resultant set of Haskell packages includes our example
    # project's packages.
    #
    haskellPackages =
        nixpkgs.haskell.packages.${config.ghcVersion}.extend overrides;

    # This function selects out packages for our example project from a set of
    # all Haskell packages.
    #
    #
    selectPackages = hsPkgs: with hsPkgs; {
        inherit
        common
        frontend
        ;
    };

    # This is an attribute set of derivations for our example project to be used
    # in a `default.nix` file.
    #
    project = selectPackages haskellPackages;

    # This is a derivation we can use with `nix-shell` to develop our project.
    # With `nix-shell` we'll get a shell environment with `PATH` set up with
    # HLS, Cabal, and a GHC loaded with all the packages we need as dependencies
    # (but not including any of the packages of our example project).
    #
    shell = haskellPackages.shellFor {

        # The transitive closure of dependencies of these packages are put in
        # the package database provided with GHC, with the exception of the
        # packages themselves.
        #
        # For instance, we we only selected out example-haskell-app, but not
        # example-haskell-lib, then example-haskell-lib would end up in the
        # package database.  However, this would be inconsequential unless we
        # removed example-haskell-lib's building from the cabal.project file.
        # Everything in cabal.project is built locally by Cabal, whether there
        # is something useable in a package database or not.
        #
        packages = hsPkgs: builtins.attrValues (selectPackages hsPkgs);

        # These are extra tools beyond GHC that we want on our PATH in our Nix
        # shell.
        #
        buildInputs = [
            hls.cabal-install
            hls.hls-renamed
            hls.hls-wrapper
            hls.implicit-hie
        ];

    };

in { inherit project shell; }
