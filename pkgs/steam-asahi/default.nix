{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  muvm,
  fex,
  fuse,
  bash,
  coreutils,
  util-linux,
  writeShellScript,
  fetchurl,
}:

let
  steamBootstrap = fetchurl {
    url = "https://repo.steampowered.com/steam/archive/stable/steam_1.0.0.81.tar.gz";
    hash = "sha256-Gia5182s4J4E3Ia1EeC5kjJX9mSltsr+b+1eRtEXtPk=";
  };

  initScript = writeShellScript "steam-asahi-init" ''
    export PATH="${lib.makeBinPath [ coreutils util-linux ]}:$PATH"

    # PulseAudio shared memory workaround (muvm guest doesn't support SHM)
    echo enable-shm=no > /run/pulse.conf

    # NixOS has no FHS paths — create them on writable tmpfs.
    # /bin/bash and /usr/bin/env are needed by scripts.
    # /usr/lib is needed by bwrap (bubblewrap) for PressureVessel/steamwebhelper.
    mkdir -p /run/fhs/bin /run/fhs/usr-bin /run/fhs/usr-lib /run/fhs/usr-lib64
    cp -a /bin/* /run/fhs/bin/ 2>/dev/null || true
    ln -sf ${bash}/bin/bash /run/fhs/bin/bash
    ln -sf ${bash}/bin/sh /run/fhs/bin/sh
    ln -sf ${coreutils}/bin/env /run/fhs/usr-bin/env
    mount --bind /run/fhs/bin /bin
    mount --bind /run/fhs/usr-bin /usr/bin

    # bwrap needs /usr/lib and /usr/lib64 to exist for bind mounts
    mkdir -p /usr/lib /usr/lib64
    mount --bind /run/fhs/usr-lib /usr/lib
    mount --bind /run/fhs/usr-lib64 /usr/lib64

    # FEX needs suid fusermount for rootfs overlay mounting
    mkdir -p /run/wrappers
    mount -t tmpfs -o exec,suid tmpfs /run/wrappers
    mkdir -p /run/wrappers/bin
    cp ${lib.getExe' fuse "fusermount"} /run/wrappers/bin/fusermount
    chown root:root /run/wrappers/bin/fusermount
    chmod u=srx,g=x,o=x /run/wrappers/bin/fusermount
  '';

  pythonEnv = python3.withPackages (ps: with ps; [ pyxdg ]);
in

stdenvNoCC.mkDerivation {
  pname = "steam-asahi";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib $out/share/steam-asahi

    # Include Steam bootstrap tarball in the package
    cp ${steamBootstrap} $out/share/steam-asahi/steam-bootstrap.tar.gz

    cp launcher.py $out/lib/steam-asahi-launcher.py

    substituteInPlace $out/lib/steam-asahi-launcher.py \
      --replace-fail "@muvm@" "${lib.getExe muvm}" \
      --replace-fail "@initScript@" "${initScript}" \
      --replace-fail "@fexRootFSFetcher@" "${fex}/bin/FEXRootFSFetcher" \
      --replace-fail "@steamBootstrap@" "$out/share/steam-asahi/steam-bootstrap.tar.gz"

    makeWrapper ${pythonEnv}/bin/python3 $out/bin/steam-asahi \
      --add-flags "$out/lib/steam-asahi-launcher.py"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Steam launcher for NixOS on Apple Silicon via muvm + FEX-Emu";
    license = licenses.mit;
    platforms = [ "aarch64-linux" ];
    mainProgram = "steam-asahi";
  };
}
