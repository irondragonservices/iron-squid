# Debian, for the squid package and everything it links against.
#
# Upstream built squid from Debian source with debuild — apt-get source,
# build-dep, a full toolchain and a patched debian/rules — and then copied the
# result out. It also referenced docker/squid.conf, which was never committed,
# so the image could not build at all. The packaged binary is the same build
# from the same maintainers, without the toolchain.
FROM debian:13.6-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132 AS build

# The version the image publishes under. Pinned, so an upgrade is a commit
# rather than something that happens on the next rebuild.
ARG SQUID_VERSION=6.13

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && apt-get install -y --no-install-recommends "squid=${SQUID_VERSION}-*" \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && squid -v | head -1

# Collect squid, its helpers, its error pages and the libraries they link
# against, preserving paths.
#
# /usr/sbin/squid is a symlink into Debian's alternatives system. cp -a
# preserves it, and /etc/alternatives is not something worth copying into a
# distroless image, so the link is resolved and the real binary copied to the
# path it is expected at. Left as a symlink, the container fails to start with
# "stat /usr/sbin/squid: no such file or directory" — which reads like the file
# is missing rather than like its target is.
#
# The library list is resolved with ldd rather than written out, so the image
# builds on any architecture. The /lib -> /usr/lib rewrite is what makes the
# result copyable into distroless: Debian is usr-merged, ldd reports the /lib
# path, and `cp --parents` materialises /out/lib as a real directory, which
# cannot be copied over distroless's /lib symlink.
RUN mkdir -p /out/usr/sbin /out/tmp \
    && chmod 1777 /out/tmp \
    && squid_bin="$(readlink -f /usr/sbin/squid)" \
    && cp -a "$squid_bin" /out/usr/sbin/squid \
    && cp -a --parents /usr/lib/squid /out \
    && cp -a --parents /usr/share/squid /out \
    && { ldd "$squid_bin"; find /usr/lib/squid -type f -exec ldd {} + 2>/dev/null || true; } \
       | tr -s ' ' | grep '=> /' | awk '{print $3}' \
       | sed -e 's|^/lib/|/usr/lib/|' -e 's|^/lib64/|/usr/lib64/|' \
       | sort -u \
       | while read -r lib; do \
           cp -a --parents "$lib" /out; \
           target="$(readlink -f "$lib")"; \
           [ "$target" != "$lib" ] && cp -a --parents "$target" /out; \
           true; \
         done

#
# ---
#

# Distroless, matched to the Debian release squid was packaged for. squid is
# copied out dynamically linked, so a mismatched glibc is a container that
# exits before it logs anything.
FROM gcr.io/distroless/base-debian13:nonroot@sha256:d199d20fb09c898d8822ae5cbd5cf3c6d424e9b5e1fc2eb9a719a7752cd9d861

LABEL org.opencontainers.image.source="https://github.com/irondragonservices/iron-squid"
LABEL org.opencontainers.image.description="Hardened base image for running Squid"

# squid, its helpers and its libraries. Not chowned to nonroot: these are
# system files and the runtime user has no business owning them.
COPY --from=build /out/usr /usr

# somewhere for the pid file and any swap state
COPY --from=build --chown=nonroot /out/tmp /tmp

COPY --chown=nonroot squid.conf /etc/squid/squid.conf

USER nonroot

EXPOSE 3128

# -N keeps squid in the foreground; without it the process daemonises and the
# container exits immediately with nothing in the log.
ENTRYPOINT ["/usr/sbin/squid"]
CMD ["-N", "-f", "/etc/squid/squid.conf"]
