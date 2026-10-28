# OST, "Observatoire Sans Tête", by Gilles (gehelem). Not in nixpkgs.
# A headless astrophotography server: INDI control, autofocus, guiding
# (PHD2), plate solving, sequencer, planner, polar alignment, all-sky.
# C++/Qt6 backend on a WebSocket (port 9624) plus a static web frontend.
# Upstream: https://github.com/gehelem/OST, docs at documentation.ostserver.fr.
#
# Upstream ships only Ubuntu .deb packages. This builds from source.
# StellarSolver (Qt6) and QtZeroConf are vendored in the source tree, so
# they come for free. The plate solver is StellarSolver's internal one:
# no astrometry.net binary needed, only its index files (see ../ost.nix).
#
# The output:
#   bin/ostserver         the server
#   lib/libost*.so        the modules, loaded at start with --libpath
#   share/ost/www         the frontend, for nginx
#   share/ostserver/      upstream's ostserver.parms.skel, as a reference
{ lib
, stdenv
, fetchFromGitHub
, cmake
, pkg-config
, qt6
, indilib
, cfitsio
, libnova
, gsl
, wcslib
, opencv
, avahi
, zlib
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ostserver";
  # Upstream tags releases on its GitLab, not on GitHub. The GitHub mirror
  # is tracked by commit; the version is CHANGELOG.md's latest entry.
  version = "0.0.19-unstable-2026-10-23";

  src = fetchFromGitHub {
    owner = "gehelem";
    repo = "OST";
    rev = "4921da608441342486c331b641868ced25466594";
    hash = "sha256-Vprhy4Yp1CLYghXhvlkLIdsJmrslEzC7X+0XozfEgQY=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    qt6.qttools # lrelease, for the .ts translations
    qt6.wrapQtAppsHook # finds the sqlite and offscreen plugins at run time
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtwebsockets
    qt6.qtscxml # Scxml and StateMachine, for Focus/Guider/Polar
    indilib # libindiclient
    cfitsio
    libnova
    gsl
    wcslib
    opencv
    avahi
    zlib
  ];

  postPatch = ''
    # Debian layout, with absolute destinations that ignore the prefix.
    substituteInPlace CMakeLists.txt \
      --replace-fail 'RUNTIME DESTINATION "/usr/bin"' 'RUNTIME DESTINATION bin' \
      --replace-fail 'LIBRARY DESTINATION "/usr/lib"' 'LIBRARY DESTINATION lib' \
      --replace-fail 'PUBLIC_HEADER DESTINATION "/usr/include/ost"' 'PUBLIC_HEADER DESTINATION include/ost' \
      --replace-fail 'DESTINATION "/var/www/pilost"' 'DESTINATION share/ost/www'

    # CPack wants git and dpkg at configure time. We don't package.
    sed -i -e '/^include(cmake\/cpack\//d' -e '/^include(CPack)/d' CMakeLists.txt

    # Both scan /usr/share. Let the service point them at the store and
    # at the index directory instead.
    substituteInPlace src/controller.cpp \
      --replace-fail 'const QString path = "/usr/share/indi";' \
        'const QString path = qEnvironmentVariable("OST_INDI_DRIVERS_DIR", "/usr/share/indi");'
    substituteInPlace src/modules/navigator/navigator.cpp \
      --replace-fail 'folders.append("/usr/share/astrometry/");' \
        'folders.append(qEnvironmentVariable("OST_ASTROMETRY_DIR", "/usr/share/astrometry/"));'
    substituteInPlace src/modules/polar/polar.cpp \
      --replace-fail 'folders.append("/usr/share/astrometry");' \
        'folders.append(qEnvironmentVariable("OST_ASTROMETRY_DIR", "/usr/share/astrometry"));'

    # Without an avahi daemon that allows publishing, avahi_entry_group_new
    # returns NULL and the next call asserts. Fail the publish instead of
    # the server: mDNS is a convenience for the Android app.
    substituteInPlace QtZeroConf/avahiclient.cpp \
      --replace-fail \
        'pri->group = avahi_entry_group_new(pri->client, QZeroConfPrivate::groupCallback, pri);' \
        'pri->group = avahi_entry_group_new(pri->client, QZeroConfPrivate::groupCallback, pri);
        if (!pri->group) {
            emit error(QZeroConf::serviceRegistrationFailed);
            return;
        }'

    # version.cc is #included by ost.cpp, by the base library and by most
    # modules. Each shared object then defines the same four std::string
    # globals. With default visibility they all resolve to one copy, and
    # every object's static destructor frees it: "double free or
    # corruption" at every exit, `-h` included. Hidden visibility gives
    # each object its own copy, built and destroyed once.
    substituteInPlace src/version.hh \
      --replace-fail 'struct Version' 'struct __attribute__((visibility("hidden"))) Version'

    # version.cc comes from `git describe`, or from the Debian changelog.
    # A fetched tarball has neither. Fill in what we know.
    cat > generate-version.sh <<'SH'
    #!/bin/sh
    sed -e 's|@GIT_SHA1@|${finalAttrs.src.rev}|g' \
        -e 's|@GIT_DATE@|${lib.last (lib.splitString "-unstable-" finalAttrs.version)}|g' \
        -e 's|@GIT_COMMIT_SUBJECT@|nixpkgs build|g' \
        -e 's|@GIT_TAG@|${finalAttrs.version}|g' \
        "$2" > "$1"
    SH
    patchShebangs generate-version.sh
  '';

  cmakeFlags = [
    # The modules and the two base libraries link each other from the
    # build tree. Without this, the installed ostserver can't find them.
    "-DCMAKE_INSTALL_RPATH=${placeholder "out"}/lib"
  ];

  postInstall = ''
    # Upstream's unit: User=ostserver, /usr/bin paths. ../ost.nix has ours.
    rm -r "$out/lib/systemd"
  '';

  meta = {
    description = "Headless astrophotography server driving INDI gear from a browser";
    homepage = "https://github.com/gehelem/OST";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "ostserver";
  };
})
