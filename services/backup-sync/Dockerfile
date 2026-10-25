FROM alpine:3.22

RUN apk add --no-cache rclone ca-certificates tzdata curl

# https://github.com/aptible/supercronic/releases
ARG TARGETARCH
ARG SUPERCRONIC_VERSION=v0.2.50
RUN set -eu; \
    case "${TARGETARCH:-amd64}" in \
      amd64) SHA1=0795da10bf6303e9680a2c2bd8dd6b9aa33ebda2 ;; \
      arm64) SHA1=e0023a0346354a153a4a2708c657308890823d14 ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    BIN="supercronic-linux-${TARGETARCH:-amd64}"; \
    curl -fsSLo /usr/local/bin/supercronic \
      "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/${BIN}"; \
    echo "${SHA1}  /usr/local/bin/supercronic" | sha1sum -c -; \
    chmod +x /usr/local/bin/supercronic

COPY entrypoint.sh sync.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/sync.sh

ENV RCLONE_CONFIG=/config/rclone/rclone.conf

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
