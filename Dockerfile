# syntax=docker/dockerfile:1
#
# E-MailRelay (https://github.com/aclemons/emailrelay) - multi-arch image
# Works natively on arm64 (aarch64) and amd64: nothing in here is
# architecture-specific, the build simply runs on whatever platform it targets.
#
# Build for arm64 on any machine (needs buildx + QEMU):
#   docker buildx build --platform linux/arm64 -t emailrelay:arm64 --load .
# Build for both:
#   docker buildx build --platform linux/arm64,linux/amd64 -t youruser/emailrelay:latest --push .

############################
# Stage 1: build
############################
FROM debian:bookworm-slim AS build

# Git ref to build: a tag, branch or commit (the repo's VERSION file says 2.6.1 on master)
ARG EMAILRELAY_REF=master

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      git \
      pkg-config \
      libssl-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone https://github.com/aclemons/emailrelay.git . \
 && git checkout "${EMAILRELAY_REF}"

# The repo ships a pre-generated ./configure, so autotools are not needed.
# GUI (Qt), PAM, docs and the test suite are disabled to keep the image small.
RUN ./configure \
      --prefix=/usr \
      --sysconfdir=/etc \
      --localstatedir=/var \
      --disable-gui \
      --disable-testing \
      --disable-install-hook \
      --without-pam \
      --without-doxygen \
      --without-man2html \
      --without-gettext \
      --with-openssl \
 && make -j"$(nproc)" \
 && make install DESTDIR=/out \
 && strip /out/usr/sbin/emailrelay* 2>/dev/null || true

############################
# Stage 2: runtime
############################
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      libssl3 \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 1000 emailrelay \
 && useradd  --system --uid 1000 --gid emailrelay --no-create-home \
             --home-dir /var/spool/emailrelay --shell /usr/sbin/nologin emailrelay \
 && mkdir -p /var/spool/emailrelay \
 && chown emailrelay:emailrelay /var/spool/emailrelay

COPY --from=build /out/ /

# Spooled messages live here - mount a volume to persist them
VOLUME ["/var/spool/emailrelay"]

# Unprivileged SMTP port (map it to 25 on the host with -p 25:10025).
# Add 110/10110 for POP if you enable --pop.
EXPOSE 10025

USER emailrelay

# Runs in the foreground, logging to stderr so `docker logs` works.
# Override the command to forward mail, e.g.:
#   docker run ... emailrelay:arm64 --log --no-daemon --as-server --port 10025 \
#       --spool-dir /var/spool/emailrelay --poll 60 --forward-to smtp.example.com:25
ENTRYPOINT ["/usr/sbin/emailrelay"]
CMD ["--log", "--no-syslog", "--verbose", "--no-daemon", "--as-server", "--port", "25", "--spool-dir", "/var/spool/emailrelay", "--remote-clients"]
