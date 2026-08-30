{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  qrtr,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "pd-mapper";
  version = "0-unstable-2025-12-30";

  src = fetchFromGitHub {
    owner = "andersson";
    repo = "pd-mapper";
    rev = "5ecd2fe926aca7abfe40724177f63b942cff3947";
    hash = "sha256-ty1Nj80DkbvJuDV3h/D1VZSMYzjSqgOqBf/6pcag7Zw=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];
  buildInputs = [ qrtr ];

  strictDeps = true;

  meta = {
    description = "Qualcomm Protection Domain mapper service";
    homepage = "https://github.com/andersson/pd-mapper";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    mainProgram = "pd-mapper";
  };
})
