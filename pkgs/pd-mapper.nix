{
  lib,
  stdenv,
  fetchFromGitHub,
  qrtr,
  xz,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "pd-mapper";
  version = "0-unstable-2025-12-30";

  src = fetchFromGitHub {
    owner = "andersson";
    repo = "pd-mapper";
    rev = "5ecd2fe926aca7abfe40724177f63b942cff3947";
    hash = "sha256-I5/N24KONtNRSub00Mqh1GoMHO2qQKTj/ts2N6DQdPc=";
  };

  # Upstream ships a plain Makefile (no meson/cmake): `make` compiles the
  # binary and links -lqrtr -llzma; `make install prefix=…` installs the
  # binary and the reference systemd unit.
  buildInputs = [ qrtr xz ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    make
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make install prefix=$out
    runHook postInstall
  '';

  strictDeps = true;

  meta = {
    description = "Qualcomm Protection Domain mapper service";
    homepage = "https://github.com/andersson/pd-mapper";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    mainProgram = "pd-mapper";
  };
})
