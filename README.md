# irondragonservices/iron-squid

Hardened [Squid](http://www.squid-cache.org) forward proxy.

Forked from [ironpeakservices/iron-squid](https://github.com/ironpeakservices/iron-squid).

Squid, its helpers and the libraries they link against, in a distroless image:
no shell, no package manager, no coreutils. Runs as `nonroot`, listens on 3128.

```sh
docker pull ghcr.io/irondragonservices/iron-squid:6
```

The tag tracks the Squid version packaged in Debian, so `:6.13` is built on
`squid=6.13-*` from `debian:13.6-slim`.

## Using it

```sh
docker run -p 3128:3128 ghcr.io/irondragonservices/iron-squid:6
```

The shipped config proxies for RFC1918 clients and refuses everything else.
**As written that accepts any private address, which is wider than most
deployments want** — narrow the `localnet` ACLs to your own ranges:

```dockerfile
FROM ghcr.io/irondragonservices/iron-squid:6
COPY --chown=nonroot squid.conf /etc/squid/squid.conf
```

There is no shell in the image, so `docker exec sh` will not work.

### What the default config does

- listens on 3128, above the privileged range, because the container is not
  root
- allows RFC1918 and link-local sources, denies everything else, denies
  `CONNECT` to anything but 443
- caches in memory only. A disk cache needs `squid -z` before first start and a
  writable spool directory, which is a lot of moving parts for a proxy that is
  usually in front of a network rather than a website
- logs access to stdout and cache events to stderr
- suppresses the version string, and strips `Via` and `X-Forwarded-For`

## Verifying what you pulled

```sh
cosign verify ghcr.io/irondragonservices/iron-squid:6 \
  --certificate-identity-regexp '^https://github.com/irondragonservices/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Changes from upstream

- **The upstream image could not build.** Its last instruction was
  `COPY docker/squid.conf /etc/squid/squid.conf`, and `docker/squid.conf` was
  never committed. The repository contained a Dockerfile, a LICENSE and a
  README, nothing else. This repository ships a config.
- **Squid is no longer compiled from Debian source.** Upstream ran `apt-get
  source`, `build-dep`, patched `debian/rules` and ran `debuild` — a full
  toolchain and a source build to arrive at the same binary the packaged
  version contains, from the same maintainers.
- **`/usr/sbin/squid` is a symlink into Debian's alternatives system.** Copied
  with `cp -a` it stays a link into `/etc/alternatives`, which does not exist
  in a distroless image, and the container fails to start with
  `stat /usr/sbin/squid: no such file or directory` — which reads like the file
  is missing rather than like its target is. The link is resolved now.
- **The helper binaries under `/usr/lib/squid` were never copied**, nor their
  libraries.
- **Base moved from `distroless/base-debian10` to `base-debian13`**, and the
  builder from `debian:buster`. Both are end of life; buster's package archives
  have moved to `archive.debian.org`.
- **`-N` added to the command.** Without it Squid daemonises and the container
  exits immediately with nothing in the log.
- **The old `CMD` passed `"--foreground -f /etc/squid/squid.conf"` as a single
  argv element**, which is not how it is parsed.
- CI rebuilt as callers into
  [irondragonservices/.github](https://github.com/irondragonservices/.github).

Verified on build: both a plain HTTP request and an HTTPS `CONNECT` return 200
through the proxy.
