# Snort 3 Automated Installer for Kali/Ubuntu/Debian

This repository provides a robust Bash script to build and install Snort 3 from source on modern Kali, Ubuntu, and Debian systems. It handles all required dependencies, resolves common package naming issues, builds LibDAQ with proper libpcap support, and makes DAQ module discovery persistent so the plain snort command works without extra flags.

## Highlights

- Installs all required dependencies with correct Debian-family names
    - Uses libdumbnet-dev (not legacy libdnet-dev)
    - Installs libpcre2-dev (required by Snort 3 CMake)
    - Ensures libpcap-dev is present before building LibDAQ (so pcap DAQ is built)
- Builds and installs LibDAQ to a custom prefix (default: /usr/local/lib/daq_s3)
- Builds and installs Snort 3 (default: /usr/local)
- Makes DAQ discovery persistent
    - System-wide alias for snort with --daq-dir
    - Adds daq_dir to snort.lua (optional) for config-based persistence
- Optional extras: asciidoc, uuid-dev, cpputest, hyperscan, etc.
- Minimizes FlatBuffers/GCC 14 warnings by default
- Clean verification steps included


## Quick Start

1) Clone and run:
```bash
git clone https://github.com/VoidTitan-x/Snort-3-Automated-Installer-for-Kali-Ubuntu-Debian.git
cd snort3-installer
sudo bash install-snort3.sh
```

2) Open a new shell or source the alias:
```bash
source /etc/profile.d/snort3.sh
```

3) Verify:
```bash
snort -V
snort --daq-list
```


## Script Options

```bash
sudo bash install-snort3.sh [options]
  --prefix PATH            Snort installation path (default: /usr/local)
  --daq-prefix PATH        DAQ installation path (default: /usr/local/lib/daq_s3)
  --no-optional            Skip optional package installation
  --hyperscan              Try installing Hyperscan (if available)
  --no-alias               Skip creating global snort alias with --daq-dir
  --no-lua-daq             Skip adding daq_dir to snort.lua
  --enable-debug           Build Snort with debug enabled
  --build-flatbuffers      Build FlatBuffers from source (may emit GCC 14 warnings)
  -h, --help               Show options
```

Examples:

- Default install:

```bash
sudo bash install-snort3.sh
```

- Custom install paths with alias:

```bash
sudo bash install-snort3.sh --prefix /opt/snort3 --daq-prefix /opt/daq_s3
```

- Minimal install without optional packages:

```bash
sudo bash install-snort3.sh --no-optional
```

- Enable debug and attempt hyperscan:

```bash
sudo bash install-snort3.sh --enable-debug --hyperscan
```


## What Gets Installed

Required:

- build-essential, autoconf, automake, libtool, pkg-config, cmake, flex, bison, g++
- libdumbnet-dev (Debian-family replacement for libdnet-dev)
- libhwloc-dev, libluajit-5.1-dev, libssl-dev
- libpcap-dev, libpcre2-dev, zlib1g-dev
- git, curl, wget, ca-certificates

Optional (if available and not skipped):

- asciidoc, w3m, source-highlight
- libunwind-dev, liblzma-dev, uuid-dev
- cpputest
- libhyperscan-dev (if requested and in repo)


## Persistent DAQ Configuration

This installer ensures Snort can always find DAQ modules when DAQ is installed to a nonstandard prefix:

- System-wide alias:
    - Creates /etc/profile.d/snort3.sh with:
        - alias snort='/usr/local/bin/snort --daq-dir /usr/local/lib/daq_s3/lib/daq'
- Optional snort.lua update:
    - Writes daq_dir = { "/usr/local/lib/daq_s3/lib/daq" } into /usr/local/etc/snort/snort.lua
    - Lets Snort find DAQ modules without needing the alias

Open a new shell or source the file to use the alias immediately:

```bash
source /etc/profile.d/snort3.sh
```


## Verification

- Show version:

```bash
snort -V
```

- List DAQ modules (should include pcap, afpacket, etc.):

```bash
snort --daq-list
```

- If you prefer not to use the alias:

```bash
/usr/local/bin/snort --daq-dir /usr/local/lib/daq_s3/lib/daq -V
/usr/local/bin/snort --daq-dir /usr/local/lib/daq_s3/lib/daq --daq-list
```


## Troubleshooting

- E: Unable to locate package libdnet-dev
    - Use libdumbnet-dev on Debian/Ubuntu/Kali (the script already does this).
- CMake error: Libpcre2 library not found
    - Install libpcre2-dev (the script already does this).
- ERROR: Could not find requested DAQ module: pcap
    - Ensure libpcap-dev was installed before building LibDAQ (the script ensures this).
    - Use the alias or ensure daq_dir is set in snort.lua.
- FlatBuffers GCC 13/14 warnings
    - Harmless warnings; ignored by default. If building FlatBuffers from source, the script suppresses noisy warnings.


## Uninstall / Rebuild Tips

- Remove installed directories if you want a clean rebuild:
    - Snort: /usr/local (or your custom prefix)
    - DAQ: /usr/local/lib/daq_s3 (or your custom prefix)
- Then rerun the installer.


## References

- Snort 3 Installation Guide
- Snort DAQ Documentation
- Snort 3 Source
- Kali Tools: Snort

Update the above links in your repository if you want to include direct references.

## License

MIT

## Maintainer

VoidTitan-x

Contributions and improvements welcome.

