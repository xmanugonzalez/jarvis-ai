#!/usr/bin/env bash
set -euo pipefail

# Bundle the phonemizer and the small wake detector. The app downloads Kokoro on demand.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
destination="build/KokoroSupport"
if [[ -f "$destination/espeak-ng-data/es_dict" && -f "$destination/Model-LICENSE.txt" &&
      -f "$destination/SherpaOnnx-LICENSE.txt" && -f "$destination/ONNXRuntime-LICENSE.txt" &&
      -f "$destination/eSpeak-NG-COPYING.txt" && -f "$destination/WakeWord/jarvis.txt" ]]; then
  exit 0
fi

mkdir -p build
stage="$(mktemp -d build/kokoro-support.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/KokoroSupport"
base="https://huggingface.co/csukuangfj/kokoro-int8-multi-lang-v1_0/resolve/57adb37fc0e8d4bd430cfc1b8f8c2294945b9af2"
curl -fsSL --retry 2 -o "$stage/data.tar.bz2" \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/espeak-ng-data.tar.bz2
check_sha() {
  if command -v shasum >/dev/null; then
    printf '%s  %s\n' "$1" "$2" | shasum -a 256 -c -
  else
    printf '%s  %s\n' "$1" "$2" | sha256sum -c -
  fi
}
check_sha 4135ccf82e1f40613491c0874d4945ae9e9c7840933d8e25a6f9e003d9ebf533 "$stage/data.tar.bz2"
tar -xjf "$stage/data.tar.bz2" -C "$stage/KokoroSupport"
wake_model="sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"
curl -fsSL --retry 2 -o "$stage/wake.tar.bz2" \
  "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/$wake_model.tar.bz2"
check_sha f170013b4716e41b62b9bfd809687c207cef798ef9bc6534d524e17af9b6561a "$stage/wake.tar.bz2"
wake_dir="$stage/KokoroSupport/WakeWord"
mkdir "$wake_dir"
suffix="-epoch-12-avg-2-chunk-16-left-64.int8.onnx"
tar -xjf "$stage/wake.tar.bz2" -C "$wake_dir" --strip-components 1 \
  "$wake_model/encoder$suffix" "$wake_model/decoder$suffix" "$wake_model/joiner$suffix" \
  "$wake_model/tokens.txt" "$wake_model/README.md"
printf '%s\n' '▁JA R VI S @Jarvis' > "$wake_dir/jarvis.txt"
curl -fsSL --retry 2 -o "$stage/KokoroSupport/Model-LICENSE.txt" "$base/LICENSE"
curl -fsSL --retry 2 -o "$stage/KokoroSupport/SherpaOnnx-LICENSE.txt" \
  https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v1.13.8/LICENSE
curl -fsSL --retry 2 -o "$stage/KokoroSupport/eSpeak-NG-COPYING.txt" \
  https://raw.githubusercontent.com/espeak-ng/espeak-ng/1.52.0/COPYING
cp "$script_dir/../licenses/ONNXRuntime-LICENSE.txt" "$stage/KokoroSupport/ONNXRuntime-LICENSE.txt"
test -f "$stage/KokoroSupport/espeak-ng-data/es_dict"
for license in Model-LICENSE.txt SherpaOnnx-LICENSE.txt eSpeak-NG-COPYING.txt ONNXRuntime-LICENSE.txt; do
  test -s "$stage/KokoroSupport/$license"
done
if [[ -e "$destination" ]]; then
  mv "$destination" "$stage/previous"
fi
mv "$stage/KokoroSupport" "$destination"
