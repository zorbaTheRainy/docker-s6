# Define the build argument (can be basic alpine for just dnsmasq/webproc,  or also caddy-alpine; tailscale can be added as S6 docker mod)
    # Alpine docker image      ->  https://hub.docker.com/_/alpine
    # S6 Overlay               ->  https://github.com/just-containers/s6-overlay
    # LinuxServer.io BaseImage ->  https://github.com/linuxserver/docker-baseimage-alpine
    # dnsmasq/webproc docker   ->  https://github.com/jpillora/docker-dnsmasq
    # Caddy docker image       ->  https://hub.docker.com/_/caddy
    # Tailscale Docker Mod     ->  https://github.com/tailscale-dev/docker-mod

# -------------------------------------------------------------------------------------------------
# How this works
# -------------------------------------------------------------------------------------------------
# This is a Dockerfile for the S6-Overlay which enables Docker mods *and* (importantly) a process manager.
# Each added service has its own:
#     * Dockerfile section
#     * <service>_run file which runs the service and is put under /etc/services-available/<service>/run (eventually symlinked to /etc/services.d/<service>/run)
#     * an ENABLE_<service> ENV is associated with the service
# When the Docker container runs:
#     * a /bin/sh script in /etc/cont-init.d runs (in S6 stage 2.i) as soon as the container runs
#     * the /bin/sh script creates the symlinks to /etc/services.d/ based on the ENV
#     * S6 (in stage 2.iii) runs any scripts in /etc/services.d/  (We are not using the new S6 stage 2.ii more complex method)
# See "Init Stages" of the S6 Overlay (https://github.com/just-containers/s6-overlay#init-stages)
# 
# TODO:
#   * there is a Docker feature where you can turn the filesystem to read-only.
#   * in that case /etc becomes unable to accept the symlinks
#   * S6 can use /var s6_installed
#   * and I should move things to there
#   * https://github.com/just-containers/s6-overlay/issues/267#issuecomment-765613028
#   * https://github.com/just-containers/s6-overlay#customizing-s6-overlay-behaviour
#   * OK!!!, I have just given up on the whole read-only fs thing.  


# -------------------------------------------------------------------------------------------------
# Stage 0: Create base image and set ENV/LABELS
# -------------------------------------------------------------------------------------------------

# set this up to copy files from the official Caddy image ( saves us worrying about the ${CADDY_VERSION} or ${TARGETARCH} )
# NOTE: Docker doesn’t directly substitute environment variables in the --from part of the COPY instruction.  We have to use FROM to handle this.  And for some reason I couldn't figure out doing these commands down in the Caddy section didn't work.
ARG CADDY_VERSION=2.8.1
FROM caddy:${CADDY_VERSION}-alpine AS caddy_donor

# set our actual BASE_IMAGE
FROM alpine:latest AS base

# passed via GitHub Action
ARG BUILD_TIME

# passed via GitHub Action (but used in Stage 1: Build)
# ARG S6_OVERLAY_VERSION=3.2.0.0
# ARG WEBPROC_VERSION=0.4.0

# Add labels to the image metadata
LABEL release-date=${BUILD_TIME}
LABEL source="https://github.com/zorbaTheRainy/dnsmasq-caddy-s6"

# -------------------------------------------------------------------------------------------------
# Stage 1: Build image
# -------------------------------------------------------------------------------------------------
FROM base AS rootfs_stage

# inherent in the build system
ARG TARGETARCH
ARG TARGETVARIANT

    # -------------------------------------------------------------------------------------------------
    # Services
    # -------------------------------------------------------------------------------------------------

    # -------------------------------------------------------------------------------------------------
    # S6 Overlay               ->  https://github.com/just-containers/s6-overlay
    # LinuxServer.io BaseImage ->  https://github.com/linuxserver/docker-baseimage-alpine
# -------------------------------------------------------------------------------------------------

# integrate the files into the file system
ADD https://tailscale.com/install.sh      /tmp/tailscale_install.sh
RUN apk update && \
    apk --no-cache add curl
RUN chmod 755 /tmp/tailscale_install.sh
# RUN /tmp/tailscale_install.sh
RUN apk add tailscale
RUN rc-update add tailscale
RUN rc-service tailscale start

    # -------------------------------------------------------------------------------------------------
    # dnsmasq/webproc docker ->  https://github.com/jpillora/docker-dnsmasq
# -------------------------------------------------------------------------------------------------

# Inputs 
ARG WEBPROC_VERSION=0.4.0
LABEL WEBPROC_VERSION=${WEBPROC_VERSION}


# Pull all the files (avoids `curl`, but causes use to pull more than we need, all archs not just one)
ENV WEBPROC_URL_ROOT  https://github.com/jpillora/webproc/releases/download/v${WEBPROC_VERSION}/webproc_${WEBPROC_VERSION}
ADD ${WEBPROC_URL_ROOT}_linux_amd64.gz      /tmp/webproc_amd64.gz
ADD ${WEBPROC_URL_ROOT}_linux_arm64.gz      /tmp/webproc_arm64.gz
ADD ${WEBPROC_URL_ROOT}_linux_armv7.gz      /tmp/webproc_armv7.gz
ADD ${WEBPROC_URL_ROOT}_linux_armv6.gz      /tmp/webproc_armv6.gz

# copy over files that run scripts  NOTE:  do NOT forget to chmod 755 them in the git folder (or they won't be executable in the image)
COPY support_files/dnsmasq/dnsmasq.conf /etc/dnsmasq.conf
COPY etc/services-available/dnsmasq_run.sh /tmp/dnsmasq_run.sh

# integrate the files into the file system
# fetch dnsmasq and webproc binary
RUN apk update && \
    apk --no-cache add dnsmasq && \
    case "${TARGETARCH}" in \
        amd64)  gzip -d -c /tmp/webproc_amd64.gz > /usr/local/bin/webproc   ;; \
        arm64)  gzip -d -c /tmp/webproc_arm64.gz > /usr/local/bin/webproc   ;; \
        arm) \
            case "${TARGETVARIANT}" in \
                v6)   gzip -d -c /tmp/webproc_armv6.gz > /usr/local/bin/webproc   ;; \
                v7)   gzip -d -c /tmp/webproc_armv7.gz > /usr/local/bin/webproc   ;; \
                v8)   gzip -d -c /tmp/webproc_arm64.gz > /usr/local/bin/webproc   ;; \
                *) echo >&2 "error: unsupported architecture (${TARGETARCH}/${TARGETVARIANT})"; exit 1 ;; \
            esac;  ;; \
        *) echo >&2 "error: unsupported architecture (${TARGETARCH}/${TARGETVARIANT})"; exit 1 ;; \
    esac  && \
    rm -rf /tmp/webproc_* && \
    chmod +x /usr/local/bin/webproc && \
    mkdir -p /etc/default/ && \
    echo -e "ENABLED=1\nIGNORE_RESOLVCONF=yes" > /etc/default/dnsmasq &&\
    mkdir -p /etc/services-available/dnsmasq && \
    mv /tmp/dnsmasq_run.sh /etc/services-available/dnsmasq/run \
    ; 

RUN if [ -f "/etc/cont-init.d/99-enable-services.sh" ]; then \
        echo 'enable_service "${ENABLE_DNSMASQ}" "dnsmasq" "DNSmasq with Webproc"' >> /etc/cont-init.d/99-enable-services.sh ; \
    fi


# Things to copy this to any Stage 2: Final image (e.g., ENV, LABEL, EXPOSE, WORKDIR, VOLUME, CMD)
EXPOSE 53/udp 8080
# ENTRYPOINT ["webproc","--configuration-file","/etc/dnsmasq.conf","--","dnsmasq","--no-daemon"]

    # -------------------------------------------------------------------------------------------------
    # Caddy docker image     ->  https://hub.docker.com/_/caddy
# -------------------------------------------------------------------------------------------------

# Inputs 
ARG CADDY_VERSION=2.8.1
LABEL CADDY_VERSION=${CADDY_VERSION}

# All of this is copied (with edits) from the Caddy Dockerfile (https://raw.githubusercontent.com/caddyserver/caddy-docker/refs/heads/master/Dockerfile.tmpl)
RUN apk add --no-cache \
	ca-certificates \
	libcap \
	mailcap

RUN mkdir -p /config/caddy /data/caddy /etc/caddy /usr/share/caddy 

# copy files from the official Caddy image ( saves us worrying about the ${CADDY_VERSION} or ${TARGETARCH} )
COPY --from=caddy_donor /etc/caddy/Caddyfile /etc/caddy/Caddyfile
COPY --from=caddy_donor /usr/share/caddy/index.html /usr/share/caddy/index.html
COPY --from=caddy_donor /usr/bin/caddy /usr/bin/caddy

RUN set -eux; \
	setcap cap_net_bind_service=+ep /usr/bin/caddy; \
	chmod +x /usr/bin/caddy; \
	caddy version

# copy over files that run scripts  NOTE:  do NOT forget to chmod 755 them in the git folder (or they won't be executable in the image)
COPY etc/services-available/caddy_run.sh /tmp/caddy_run.sh
RUN mkdir -p /etc/services-available/caddy && \
    mv /tmp/caddy_run.sh /etc/services-available/caddy/run && \
    chmod +x /etc/services-available/caddy/run && \
    if [ -f "/etc/cont-init.d/99-enable-services.sh" ]; then \
        echo 'enable_service "${ENABLE_CADDY}" "caddy" "Caddy reverse proxy"' >> /etc/cont-init.d/99-enable-services.sh ; \
    fi

# Things to copy to any Stage 2: Final image (e.g., ENV, LABEL, EXPOSE, WORKDIR, VOLUME, CMD)
ENV CADDY_VERSION v${CADDY_VERSION}
ENV XDG_CONFIG_HOME /configuration
ENV XDG_DATA_HOME /data
EXPOSE 80
EXPOSE 443
EXPOSE 443/udp
EXPOSE 2019
# CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

# -------------------------------------------------------------------------------------------------
# Stage 2: Final image
# -------------------------------------------------------------------------------------------------

# by using 'base' (which was set earlier, this image inherets any already set ENV/LABEL in Stage 0)
FROM base
# Copy the entire filesystem from the builder stage
COPY --from=rootfs_stage / /
COPY support_files/.bashrc /root/.bashrc

# enable variables
ENV ENABLE_DNSMASQ true
ENV ENABLE_CADDY true

# Things copied from an old Stage 1: Build image (e.g., ENV, LABEL, EXPOSE, WORKDIR, VOLUME, CMD)
ARG S6_OVERLAY_VERSION=3.2.0.0
LABEL S6_OVERLAY_VERSION=${S6_OVERLAY_VERSION}
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=1
ARG MODS_VERSION="v3"
ARG PKG_INST_VERSION="v1"
ARG LSIOWN_VERSION="v1"
ENV PS1="$(whoami)@$(hostname):$(pwd)\\$ " \
  HOME="/root" \
  TERM="xterm" \
  S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" \
  S6_VERBOSITY=1 \
  S6_STAGE2_HOOK=/docker-mods \
  VIRTUAL_ENV=/lsiopy \
  PATH="/lsiopy/bin:$PATH"

ARG WEBPROC_VERSION=0.4.0
LABEL WEBPROC_VERSION=${WEBPROC_VERSION}
EXPOSE 53/udp 8080

ARG CADDY_VERSION=2.8.1
LABEL CADDY_VERSION=${CADDY_VERSION}
ENV CADDY_VERSION v${CADDY_VERSION}
ENV XDG_CONFIG_HOME /config
ENV XDG_DATA_HOME /data
EXPOSE 80 443 443/udp
EXPOSE 2019

# Run the desired programs
ENTRYPOINT ["/init"]
