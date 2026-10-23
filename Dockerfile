# syntax=docker/dockerfile:1
#
# E-MailRelay (https://github.com/aclemons/emailrelay) - Alpine multi-arch image
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
FROM alpine:3.22 AS build

# Git ref to build: a tag, branch or commit (the repo's VERSION file says 2.6.1 on master)
ARG EMAILRELAY_REF=master

RUN apk add --no-cache \
      build-base \
      git \
      linux-headers \
      openssl-dev \
      pkgconf

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
 && (strip /out/usr/sbin/emailrelay* 2>/dev/null || true)

############################
# Stage 2: runtime
############################
FROM alpine:3.22

RUN apk add --no-cache \
      ca-certificates \
      libstdc++ \
      libgcc \
      libssl3 \
      libcrypto3 \
 && addgroup -S -g 1000 emailrelay \
 && adduser  -S -u 1000 -G emailrelay -H -h /var/spool/emailrelay -s /sbin/nologin emailrelay \
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
CMD []
