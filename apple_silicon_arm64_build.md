# Apple Silicon (arm64) version of cd2netmd_gui

This is a first attempt at getting NetMD Wizard built and running natively on Apple Silicone Macs 
as Intel builds will be dropped on the next MacOS (Golden Gate) release.

This is the process of replacing the Intel built libraries under `prebuilt/mac/` and fixing a transfer issue with netmd_plusplus.

## 1. Install arm64 dependencies via Homebrew

Confirm you're on arm64 Homebrew first (`brew --prefix` should print
`/opt/homebrew`, not `/usr/local`), then:

```bash
brew install libcdio libcdio-paranoia taglib libvorbis libogg opus \
             flac libsndfile libgcrypt libusb pkg-config qt@5 ffmpeg
```

## 2. Setup a source code location 

I am going to assume the location will be `~/SourceCode`

```bash
mkdir SourceCode && cd SourceCode
```

## 2. Clone my fork 

git clone https://github.com/ghostseven/cd2netmd_gui.git

## 3. Build my `netmd_plusplus` fork for arm64

This is forked as there is a bug either in the latest MacOS or libusb that prevents bulkTransfer() from occurring unless you scale the transfer back by one byte (or more) it times out.
A very odd bug that is now addressed, also I needed to roll back from the latest commit to allow functionality that is missing or changed (this needs to be further investigated)

```bash
cd ~/SourceCode
git clone https://github.com/ghostseven/netmd_plusplus.git
cd netmd_plusplus
mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX=/opt/homebrew ..
make -j$(sysctl -n hw.ncpu)
make install
pkg-config --exists libnetmd++ && echo OK
```

## 4. Build `atracdenc` for arm64

Source: https://github.com/dcherednik/atracdenc

```bash
cd ~/SourceCode
git clone https://github.com/dcherednik/atracdenc.git
cd atracdenc
git submodule update --init --recursive
```

Change the CMakeLists.txt to build just for arm64 otherwise it fails to build when attempting both.

```bash
sed -i '' 's/^\( *\)set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")/\1# &  # arm64-only build/' CMakeLists.txt
```

```bash
mkdir build && cd build
cmake ..
make -j$(sysctl -n hw.ncpu)
```

Copy the resulting binary into the tree where `cd2netmd_gui.pro` and
`create_mac_bundle.sh` expect it:

```bash
cp build/src/atracdenc ~/SourceCode/cd2netmd_gui/prebuilt/mac/bin/atracdenc
```

## 5. Build the app

```bash
cd ~/SourceCode/cd2netmd_gui
qmake cd2netmd_gui.pro
make -j$(sysctl -n hw.ncpu)
```

## 6. Patch `create_mac_bundle.sh`

```bash
./create_mac_bundle.sh release
```

## 7. Bundle `atracdenc`'s runtime dependencies

`atracdenc` dynamically links `libsndfile`, which transitively pulls in
`libogg`, `libvorbis`, `libvorbisenc`, `libFLAC`, `libopus`, `libmpg123`,
and `libmp3lame` — none of which `macdeployqt` knows to walk into, since
it only sees `atracdenc` as a copied file, not a linked dependency of the
Qt app itself.

Use `fixup_atracdenc_deps.sh` to auto-discover the full transitive dependency
tree, copy each `.dylib` into `Contents/Frameworks/`, and rewrite every
load command to `@executable_path/../Frameworks/...` so the bundle
doesn't require Homebrew on the end user's machine:

```bash
./fixup_atracdenc_deps.sh "release/netmd_wizard_mac_/NetMD Wizard.app"
```

## 8. Re-sign and test

`install_name_tool` invalidates code signatures. Re-sign ad-hoc before
running:

```bash
cd "release/netmd_wizard_mac_/NetMD Wizard.app"
codesign --force --deep --sign - "Contents/MacOS/atracdenc"
for f in Contents/Frameworks/*.dylib; do codesign --force --sign - "$f"; done
codesign --force --deep --sign - .
cd -
open "release/netmd_wizard_mac_/NetMD Wizard.app"
```
