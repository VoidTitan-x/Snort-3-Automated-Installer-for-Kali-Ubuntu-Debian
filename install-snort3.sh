#!/usr/bin/env bash
set -euo pipefail

# Snort 3 complete installer for Debian/Ubuntu/Kali
# Features:
# - Installs required deps (Debian-family names: libdumbnet-dev, libpcre2-dev, libpcap-dev)
# - Optional deps toggleable
# - Builds LibDAQ with custom prefix and ensures pcap DAQ
# - Builds Snort 3 with correct DAQ include/lib hints
# - Persists DAQ discovery via system alias and optional snort.lua config
# - Minimizes FlatBuffers/GCC14 warnings by default (no source build unless requested)

# Options
PREFIX="/usr/local"
DAQ_PREFIX="/usr/local/lib/daq_s3"
INSTALL_OPTIONAL=1
INSTALL_HYPERSCAN=0         # Set to 1 to install hyperscan (from repo if available)
SET_DAQ_ALIAS=1
WRITE_SNORT_LUA_DAQ=1       # Write daq_dir into snort.lua if present
ENABLE_DEBUG=0
BUILD_FLATBUFFERS=0         # Set to 1 to build flatbuffers from source (may warn on GCC14)

usage() {
  cat <<EOF
Usage: sudo bash $0 [options]
  --prefix PATH            Snort install prefix (default: /usr/local)
  --daq-prefix PATH        LibDAQ install prefix (default: /usr/local/lib/daq_s3)
  --no-optional            Skip optional package installation
  --hyperscan              Attempt to install Hyperscan
  --no-alias               Do not create system-wide snort alias with --daq-dir
  --no-lua-daq             Do not modify snort.lua to set daq_dir
  --enable-debug           Enable Snort debug mode
  --build-flatbuffers      Build flatbuffers from source (may emit GCC 14 warnings)
  -h|--help                Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:?}"; shift 2;;
    --daq-prefix) DAQ_PREFIX="${2:?}"; shift 2;;
    --no-optional) INSTALL_OPTIONAL=0; shift;;
    --hyperscan) INSTALL_HYPERSCAN=1; shift;;
    --no-alias) SET_DAQ_ALIAS=0; shift;;
    --no-lua-daq) WRITE_SNORT_LUA_DAQ=0; shift;;
    --enable-debug) ENABLE_DEBUG=1; shift;;
    --build-flatbuffers) BUILD_FLATBUFFERS=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (use sudo)."
  exit 1
fi

echo "========== Snort 3 Installer =========="
echo "Snort prefix      : $PREFIX"
echo "LibDAQ prefix     : $DAQ_PREFIX"
echo "Optional packages : $INSTALL_OPTIONAL"
echo "Hyperscan         : $INSTALL_HYPERSCAN"
echo "Alias snort       : $SET_DAQ_ALIAS"
echo "Write snort.lua   : $WRITE_SNORT_LUA_DAQ"
echo "Debug build       : $ENABLE_DEBUG"
echo "Build flatbuffers : $BUILD_FLATBUFFERS"
echo "======================================="

# Verify apt-based system
if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script targets Debian/Ubuntu/Kali (apt)."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Required packages (Debian-family names)
# Notes:
# - libdumbnet-dev replaces legacy libdnet-dev on Debian/Ubuntu/Kali
# - libpcre2-dev is required by Snort 3 (PCRE2), not libpcre3-dev
# - libpcap-dev must be present BEFORE building LibDAQ to get pcap DAQ
apt-get install -y \
  git wget curl ca-certificates \
  build-essential autoconf automake libtool pkg-config cmake \
  flex bison g++ \
  libdumbnet-dev \
  libhwloc-dev \
  libluajit-5.1-dev \
  libssl-dev \
  libpcap-dev \
  libpcre2-dev \
  zlib1g-dev

# Optional packages
if [[ $INSTALL_OPTIONAL -eq 1 ]]; then
  apt-get install -y \
    asciidoc w3m source-highlight \
    libunwind-dev liblzma-dev uuid-dev \
    cpputest || true
  # Hyperscan (if requested and available)
  if [[ $INSTALL_HYPERSCAN -eq 1 ]]; then
    apt-get install -y libhyperscan-dev || true
  fi
fi

WORKDIR="${TMPDIR:-/tmp}/snort3-build-$(date +%s)"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Optionally build flatbuffers from source (off by default)
if [[ $BUILD_FLATBUFFERS -eq 1 ]]; then
  echo "Building flatbuffers from source..."
  git clone https://github.com/google/flatbuffers.git
  mkdir -p flatbuffers-build && cd flatbuffers-build
  # Suppress GCC14 stringop warnings commonly seen in reflection.cpp
  CXXFLAGS="-Wno-stringop-overflow -Wno-stringop-overread" cmake ../flatbuffers -DCMAKE_BUILD_TYPE=Release
  make -j"$(nproc)"
  make install
  ldconfig
  cd "$WORKDIR"
fi

# Build and install LibDAQ
echo "Cloning and building LibDAQ..."
git clone https://github.com/snort3/libdaq.git
cd libdaq
./bootstrap
./configure --prefix="$DAQ_PREFIX"
# Show summary line to ensure pcap is built; grep is non-fatal
make clean >/dev/null 2>&1 || true
./configure --prefix="$DAQ_PREFIX" | tee /tmp/daq_configure.log
grep -i "Build PCAP DAQ module" /tmp/daq_configure.log || true
make -j"$(nproc)"
make install

# ldconfig path for custom DAQ install
if [[ "$DAQ_PREFIX" != "/usr" && "$DAQ_PREFIX" != "/usr/local" ]]; then
  echo "$DAQ_PREFIX/lib/" > /etc/ld.so.conf.d/libdaq3.conf
fi
ldconfig
cd "$WORKDIR"

# Build and install Snort 3
echo "Cloning and building Snort 3..."
git clone https://github.com/snort3/snort3.git
cd snort3

CONFIG_OPTS=( "--prefix=$PREFIX" )
if [[ "$DAQ_PREFIX" != "/usr" && "$DAQ_PREFIX" != "/usr/local" ]]; then
  CONFIG_OPTS+=( "--with-daq-includes=$DAQ_PREFIX/include/" )
  CONFIG_OPTS+=( "--with-daq-libraries=$DAQ_PREFIX/lib/" )
fi
if [[ $ENABLE_DEBUG -eq 1 ]]; then
  CONFIG_OPTS+=( "--enable-debug" )
fi

./configure_cmake.sh "${CONFIG_OPTS[@]}"

cd build
make -j"$(nproc)"
make install

# ldconfig for custom Snort library paths if needed
if [[ "$PREFIX" != "/usr" && "$PREFIX" != "/usr/local" ]]; then
  echo "# Snort3 custom libs" > /etc/ld.so.conf.d/snort3.conf
  [[ -d "$PREFIX/lib" ]] && echo "$PREFIX/lib" >> /etc/ld.so.conf.d/snort3.conf
  [[ -d "$PREFIX/lib64" ]] && echo "$PREFIX/lib64" >> /etc/ld.so.conf.d/snort3.conf
  ldconfig
else
  ldconfig
fi

SNORT_BIN="$PREFIX/bin/snort"
DAQ_DIR="$DAQ_PREFIX/lib/daq"

echo "Verifying DAQ modules..."
if [[ -x "$SNORT_BIN" ]]; then
  if "$SNORT_BIN" --daq-list >/dev/null 2>&1; then
    "$SNORT_BIN" --daq-list || true
  else
    if [[ -d "$DAQ_DIR" ]]; then
      "$SNORT_BIN" --daq-dir "$DAQ_DIR" --daq-list || true
    fi
  fi
fi

# Persistent alias (system-wide) so 'snort' finds DAQ modules without flags
if [[ $SET_DAQ_ALIAS -eq 1 ]]; then
  PROFILE_FILE="/etc/profile.d/snort3.sh"
  echo "alias snort='$SNORT_BIN --daq-dir $DAQ_DIR'" > "$PROFILE_FILE"
  chmod +x "$PROFILE_FILE"
fi

# Optionally write daq_dir into snort.lua if exists or create minimal config
if [[ $WRITE_SNORT_LUA_DAQ -eq 1 ]]; then
  SNORT_ETC="$PREFIX/etc/snort"
  mkdir -p "$SNORT_ETC"
  LUA_FILE="$SNORT_ETC/snort.lua"
  if [[ ! -f "$LUA_FILE" ]]; then
    cat > "$LUA_FILE" <<EOF
-- Minimal Snort 3 config
daq_dir = { "$DAQ_DIR" }
EOF
  else
    # Append daq_dir if not present
    if ! grep -q "daq_dir" "$LUA_FILE"; then
      echo "daq_dir = { \"$DAQ_DIR\" }" >> "$LUA_FILE"
    fi
  fi
fi

echo ""
echo "================ Installation Complete ================"
echo "Snort binary : $SNORT_BIN"
echo "Snort prefix : $PREFIX"
echo "LibDAQ prefix: $DAQ_PREFIX"
echo ""
echo "Check version:"
echo "  $SNORT_BIN -V"
echo ""
echo "DAQ modules:"
echo "  $SNORT_BIN --daq-dir $DAQ_DIR --daq-list"
echo ""
if [[ $SET_DAQ_ALIAS -eq 1 ]]; then
  echo "An alias was created in /etc/profile.d/snort3.sh."
  echo "Open a new shell or run: source /etc/profile.d/snort3.sh"
fi
if [[ $WRITE_SNORT_LUA_DAQ -eq 1 ]]; then
  echo "Configured DAQ directory in: $PREFIX/etc/snort/snort.lua"
fi
echo "======================================================="
