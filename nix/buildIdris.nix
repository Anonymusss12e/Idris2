{ stdenv, lib, idris2Version, idris2, support, makeWrapper }:
# Usage: let
#          pkg = idris2Pkg.buildIdris {
#            src = ...;
#            ipkgName = "my-pkg";
#            idrisLibraries = [ ];
#          };
#        in {
#          lib = pkg.library { withSource = true; };
#          bin = pkg.executable;
#        }
#
{ src
, ipkgName
, version ? "unversioned"
, idrisLibraries
, ... }@attrs:

let
  ipkgFileName = ipkgName + ".ipkg";
  idrName = "idris2-${idris2Version}";
  libSuffix = "lib/${idrName}";
  libDirs =
    lib.strings.makeSearchPath libSuffix idrisLibraries;
  drvAttrs = builtins.removeAttrs attrs [
    "ipkgName"
    "idrisLibraries"
  ];

  sharedAttrs = drvAttrs // {
    pname = ipkgName;
    inherit version;
    src = src;
    nativeBuildInputs = [ idris2 makeWrapper ] ++ attrs.nativeBuildInputs or [];
    buildInputs = idrisLibraries ++ attrs.buildInputs or [];

    IDRIS2_PACKAGE_PATH = libDirs;

    buildPhase = ''
      runHook preBuild
      idris2 --build ${ipkgFileName}
      runHook postBuild
    '';
  };

in rec {
  executable = stdenv.mkDerivation (sharedAttrs //
    { installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        scheme_app="$(find ./build/exec -name '*_app')"
        if [ "$scheme_app" = ''' ]; then
          mv -- build/exec/* $out/bin/
          chmod +x $out/bin/*
          # ^ remove after Idris2 0.8.0 is released. will be superfluous:
          # https://github.com/idris-lang/Idris2/pull/3189
        else
          cd build/exec/*_app
          rm -f ./libidris2_support.so
          for file in *.so; do
            bin_name="''${file%.so}"
            mv -- "$file" "$out/bin/$bin_name"
            wrapProgram "$out/bin/$bin_name" \
              --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ support ]} \
              --prefix DYLD_LIBRARY_PATH : ${lib.makeLibraryPath [ support ]}
          done
        fi
        runHook postInstall
      '';
    }
  );

  library = { withSource ? false }:
    let installCmd = if withSource then "--install-with-src" else "--install";
    in stdenv.mkDerivation (sharedAttrs //
      { installPhase = ''
          runHook preInstall
          mkdir -p $out/${libSuffix}
          export IDRIS2_PREFIX=$out/lib
          idris2 ${installCmd} ${ipkgFileName}
          runHook postInstall
        '';
      }
    );
  # deprecated aliases:
  build = lib.warn "build is a deprecated alias for 'executable'." executable;
  installLibrary = lib.warn "installLibrary is a deprecated alias for 'library { }'." (library { });
}
