#!/bin/sh
set -e

# Inputs
S6_OVERLAY_VERSION=${S6_OVERLAY_VERSION:-3.2.0.0}
S6_URL_ROOT=https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}

# Function to detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo $ID
    else
        echo "unknown"
    fi
}

# Function to download files if they don't already exist
download_if_not_exists() {
    local url=$1
    local dest=$2
    if [ ! -f $dest ]; then
        wget $url -O $dest
    else
        echo "File $dest already exists. Skipping download."
    fi
}

# Pull all the files
download_if_not_exists "${S6_URL_ROOT}/s6-overlay-noarch.tar.xz" "/tmp/s6-overlay-noarch.tar.xz"
download_if_not_exists "${S6_URL_ROOT}/s6-overlay-symlinks-noarch.tar.xz" "/tmp/s6-overlay-symlinks-noarch.tar.xz"
download_if_not_exists "${S6_URL_ROOT}/s6-overlay-symlinks-arch.tar.xz" "/tmp/s6-overlay-symlinks-yesarch.tar.xz"
download_if_not_exists "${S6_URL_ROOT}/s6-overlay-x86_64.tar.xz" "/tmp/s6-overlay-yesarch-amd64.tar.xz"
download_if_not_exists "${S6_URL_ROOT}/s6-overlay-aarch64.tar.xz" "/tmp/s6-overlay-yesarch-arm64.tar.xz"
download_if_not_exists "${S6_URL_ROOT}/s6-overlay-arm.tar.xz" "/tmp/s6-overlay-yesarch-armv7.tar.xz"
download_if_not_exists "${S6_URL_ROOT}/s6-overlay-armhf.tar.xz" "/tmp/s6-overlay-yesarch-armv6.tar.xz"

DISTRO=$(detect_distro)
echo "Detected Linux distribution: $DISTRO"

# Integrate the files into the file system
case "$DISTRO" in
    alpine)
        apk update
        apk add --no-cache bash xz
        ;;
    arch)
        pacman -Syu --noconfirm
        pacman -S --noconfirm bash xz
        ;;
    debian|ubuntu)
        apt-get update
        apt-get install -y bash xz-utils
        ;;
    fedora)
        dnf update -y
        dnf install -y bash xz
        ;;
    *)
        echo "Unsupported Linux distribution: $DISTRO"
        exit 1
        ;;
esac

case "${TARGETARCH}" in
    amd64)  mv /tmp/s6-overlay-yesarch-amd64.tar.xz /tmp/s6-overlay-yesarch.tar.xz  ;;
    arm64)  mv /tmp/s6-overlay-yesarch-arm64.tar.xz /tmp/s6-overlay-yesarch.tar.xz  ;;
    arm)
        case "${TARGETVARIANT}" in
            v6)   mv /tmp/s6-overlay-yesarch-armv6.tar.xz /tmp/s6-overlay-yesarch.tar.xz  ;;
            v7)   mv /tmp/s6-overlay-yesarch-armv7.tar.xz /tmp/s6-overlay-yesarch.tar.xz  ;;
            v8)   mv /tmp/s6-overlay-yesarch-arm64.tar.xz /tmp/s6-overlay-yesarch.tar.xz  ;;
            *) echo >&2 "error: unsupported architecture (${TARGETARCH}/${TARGETVARIANT})"; exit 1 ;;
        esac ;;
    *) echo >&2 "error: unsupported architecture (${TARGETARCH}/${TARGETVARIANT})"; exit 1 ;;
esac

tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz
tar -C / -Jxpf /tmp/s6-overlay-yesarch.tar.xz
tar -C / -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz
tar -C / -Jxpf /tmp/s6-overlay-symlinks-yesarch.tar.xz
rm -f /tmp/s6-overlay-*.tar.xz
mkdir -p /etc/services.d/
mkdir -p /etc/services-available
mkdir -p /etc/cont-init.d/
mv /tmp/99-enable-services.sh /etc/cont-init.d/99-enable-services.sh
chmod 755 /etc/cont-init.d/99-enable-services.sh

# Additional steps for LinuxServer.io
MODS_VERSION="v3"
PKG_INST_VERSION="v1"
LSIOWN_VERSION="v1"
LSIO_RELEASE_VERSION="3.20-2a6ecb14-ls14"

download_if_not_exists "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/docker-mods.${MODS_VERSION}" "/docker-mods"
download_if_not_exists "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/package-install.${PKG_INST_VERSION}" "/etc/s6-overlay/s6-rc.d/init-mods-package-install/run"
download_if_not_exists "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/lsiown.${LSIOWN_VERSION}" "/usr/bin/lsiown"
chmod 755 /docker-mods /etc/s6-overlay/s6-rc.d/init-mods-package-install/run /usr/bin/lsiown

# Environment setup
export PS1="$(whoami)@$(hostname):$(pwd)\\$ " 
export HOME="/root" 
export TERM="xterm" 
export S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" 
export S6_VERBOSITY=1 
export S6_STAGE2_HOOK=/docker-mods 
export VIRTUAL_ENV=/lsiopy 
export PATH="/lsiopy/bin:$PATH"


case "$DISTRO" in
    alpine)
        echo "**** install runtime packages ****"
        apk add --no-cache \
            alpine-release \
            bash \
            ca-certificates \
            catatonit \
            coreutils \
            curl \
            findutils \
            jq \
            netcat-openbsd \
            procps-ng \
            shadow \
            tzdata

        echo "**** create abc user and make our folders ****"
        groupmod -g 1000 users
        useradd -u 911 -U -d /config -s /bin/false abc
        usermod -G users abc
        mkdir -p /app /config /defaults /lsiopy

        echo "**** cleanup ****"
        rm -rf /tmp/*
        ;;
    arch)
        echo "**** install runtime packages ****"
        pacman -Syu --noconfirm
        pacman -S --noconfirm \
            ca-certificates \
            catatonit \
            coreutils \
            curl \
            findutils \
            jq \
            netcat \
            procps-ng \
            shadow \
            tzdata

        echo "**** create abc user and make our folders ****"
        groupmod -g 1000 users
        useradd -u 911 -U -d /config -s /bin/false abc
        usermod -G users abc
        mkdir -p /app /config /defaults /lsiopy

        echo "**** cleanup ****"
        rm -rf /tmp/*
        ;;
    debian|ubuntu)
        echo "**** install runtime packages ****"
        apt-get update
        apt-get install -y \
            ca-certificates \
            catatonit \
            coreutils \
            curl \
            findutils \
            jq \
            netcat \
            procps \
            shadow-utils \
            tzdata

        echo "**** create abc user and make our folders ****"
        groupmod -g 1000 users
        useradd -u 911 -U -d /config -s /bin/false abc
        usermod -G users abc
        mkdir -p /app /config /defaults /lsiopy

        echo "**** cleanup ****"
        rm -rf /tmp/*
        ;;
    fedora)
        echo "**** install runtime packages ****"
        dnf update -y
        dnf install -y \
            ca-certificates \
            catatonit \
            coreutils \
            curl \
            findutils \
            jq \
            nc \
            procps-ng \
            shadow-utils \
            tzdata

        echo "**** create abc user and make our folders ****"
        groupmod -g 1000 users
        useradd -u 911 -U -d /config -s /bin/false abc
        usermod -G users abc
        mkdir -p /app /config /defaults /lsiopy

        echo "**** cleanup ****"
        rm -rf /tmp/*
        ;;
    *)
        echo "Unsupported Linux distribution: $DISTRO"
        exit 1
        ;;
esac

# Copy files from the official LinuxServices.io Alpine image's GitHub
download_if_not_exists "https://github.com/linuxserver/docker-baseimage-alpine/archive/refs/tags/${LSIO_RELEASE_VERSION}.tar.gz" "/tmp/${LSIO_RELEASE_VERSION}.tar.gz"
tar -C /tmp -xzvf /tmp/${LSIO_RELEASE_VERSION}.tar.gz
cp -a /tmp/docker-baseimage-alpine-${LSIO_RELEASE_VERSION}/root/etc/s6-overlay/s6-rc.d /etc/s6-overlay/
rm -rf /tmp/*
