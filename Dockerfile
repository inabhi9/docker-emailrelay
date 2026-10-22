FROM debian:bookworm-slim

ARG EMAILRELAY_VERSION=master

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        libssl-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

RUN git clone --depth 1 --branch "${EMAILRELAY_VERSION}" https://github.com/aclemons/emailrelay.git /tmp/emailrelay \
    && cd /tmp/emailrelay \
    && ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
    && make -j"$(nproc)" \
    && make install \
    && cd / \
    && rm -rf /tmp/emailrelay

RUN useradd --system --create-home --home-dir /var/lib/emailrelay emailrelay || true

EXPOSE 25 10025 10110

ENTRYPOINT ["/usr/bin/emailrelay"]
CMD ["--help"]