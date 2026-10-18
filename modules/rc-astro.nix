{ config, lib, pkgs, ... }:

# RC-Astro CLI, by Russell Croman. Proprietary, not in nixpkgs.
# BlurXTerminator, NoiseXTerminator and StarXTerminator from the shell:
#   rc-astro bxt input.tif
#   rc-astro --device            # list the compute devices
#   rc-astro license <code>      # activate, with the code from rc-astro.com/account
#
# Upstream ships a self-extracting .sh: a shell stub, then a gzipped tar
# after a marker line. The payload is the rc-astro binary, ONNX Runtime and
# its CUDA execution provider. They expect libstdc++ and, for the GPU, the
# CUDA 12 runtime, cuBLAS, cuFFT and cuDNN 9 in FHS paths, which NixOS
# lacks. autoPatchelfHook rewrites their RUNPATHs to the store instead.
#
# GPU inference needs an NVIDIA card. The CUDA libraries are linked in only
# on hosts that load the nvidia driver (gamix). Elsewhere the 680 MB
# provider is dropped and rc-astro runs on the CPU.
# libcuda.so.1 ships with the driver, in /run/opengl-driver/lib. That path
# goes on the RUNPATH too, so rc-astro can enumerate the GPUs.
#
# Config and license state live in ~/.config/RC-Astro. The ML models are
# not bundled; rc-astro downloads them on first use (or `download-models`).
# Its `update` command cannot write to the store. Bump `version` and `hash`
# here instead. The hashes are published at
# https://www.rc-astro.com/resources/versions.json (hex sha256, convert
# with `nix hash convert --hash-algo sha256 <hex>`).
let
  withCuda = builtins.elem "nvidia" config.services.xserver.videoDrivers;

  cudaLibs = map lib.getLib (with pkgs.cudaPackages; [
    cuda_cudart # libcudart.so.12
    libcublas # libcublas.so.12, libcublasLt.so.12
    libcufft # libcufft.so.11
    cudnn # libcudnn.so.9
  ]);

  rc-astro = pkgs.stdenv.mkDerivation (finalAttrs: {
    pname = "rc-astro";
    version = "2.6.10";

    src = pkgs.fetchurl {
      url = "https://www.rc-astro-cdn.com/clients/${finalAttrs.version}/rc-astro-cli-${finalAttrs.version}-linux-x64.sh";
      hash = "sha256-jY+3w4Z/SeTYEk9S1fF0pKud+kMJ/65d1brcg2Uc8jc=";
    };

    nativeBuildInputs = with pkgs; [ autoPatchelfHook ];

    buildInputs = [
      pkgs.stdenv.cc.cc.lib # libstdc++, libgcc_s
    ] ++ lib.optionals withCuda cudaLibs;

    # rc-astro also dlopens the CUDA libraries by soname, for its device
    # listing. autoPatchelf only follows NEEDED entries, so add them to
    # every RUNPATH explicitly.
    runtimeDependencies = lib.optionals withCuda cudaLibs;
    appendRunpaths = lib.optionals withCuda [ "/run/opengl-driver/lib" ];

    unpackPhase = ''
      runHook preUnpack
      mkdir source
      marker=$(awk '/^__RCAC_PAYLOAD_BELOW__$/ { print NR + 1; exit }' "$src")
      tail -n "+$marker" "$src" | tar xzf - -C source
      runHook postUnpack
    '';
    sourceRoot = "source";

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      # Keep the upstream layout: ONNX Runtime finds its provider libraries
      # next to itself, and rc-astro finds libonnxruntime through $ORIGIN.
      app="$out/opt/rc-astro"
      mkdir -p "$app" "$out/bin"
      cp -a rc-astro libonnxruntime.so.1 libonnxruntime.so.1.23.2 \
        librca_onnxruntime_providers_shared.so rsc "$app/"
      ${lib.optionalString withCuda ''
        cp -a librca_onnxruntime_providers_cuda.so "$app/"
      ''}
      ln -s "$app/rc-astro" "$out/bin/rc-astro"

      install -Dm644 -t "$out/share/doc/rc-astro" README-DEVS.md THIRD-PARTY.txt
      install -Dm644 -t "$out/share/licenses/rc-astro" LICENSE.txt

      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "BlurXTerminator, NoiseXTerminator and StarXTerminator for the command line";
      homepage = "https://www.rc-astro.com/";
      license = licenses.unfree;
      platforms = [ "x86_64-linux" ];
      mainProgram = "rc-astro";
      sourceProvenance = [ sourceTypes.binaryNativeCode ];
    };
  });
in
{
  environment.systemPackages = [ rc-astro ];
}
