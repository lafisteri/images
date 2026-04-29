ARG CHROME_VERSION
ARG CHROME_APT_PATTERN=""
ARG DRIVER_VERSION
ARG ENABLE_VNC=0
ARG LOCALE="en_US.UTF-8"
ARG TZ="UTC"

FROM golang:1.22-bullseye AS devtools-builder

WORKDIR /src/devtools

COPY devtools/go.mod .
COPY devtools/go.sum .
COPY devtools/*.go .

ENV GOPROXY=https://proxy.golang.org,direct \
    GO111MODULE=on

RUN go mod tidy -e && \
    go mod verify && \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/devtools

FROM golang:1.22-bullseye AS fileserver-builder

WORKDIR /src/fileserver

COPY fileserver/go.mod ./
COPY fileserver/*.go ./

ENV GOPROXY=https://proxy.golang.org,direct \
    GO111MODULE=on

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/fileserver

FROM golang:1.22-bullseye AS xseld-builder

WORKDIR /src/xseld

COPY xseld/go.mod ./
COPY xseld/*.go ./

ENV GOPROXY=https://proxy.golang.org,direct \
    GO111MODULE=on

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/xseld

FROM debian:bullseye-slim

ARG CHROME_VERSION
ARG CHROME_APT_PATTERN=""
ARG DRIVER_VERSION
ARG ENABLE_VNC=0
ARG LOCALE="en_US.UTF-8"
ARG TZ="UTC"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ="${TZ}" \
    LANG="${LOCALE}" \
    LANGUAGE="${LOCALE}" \
    LC_ALL="${LOCALE}" \
    DISPLAY=:99 \
    SCREEN_RESOLUTION=1920x1080x24 \
    CHROME_BIN=/usr/bin/google-chrome \
    CHROMEDRIVER=/usr/bin/chromedriver \
    DBUS_SESSION_BUS_ADDRESS=/dev/null \
    ENABLE_VNC="${ENABLE_VNC}"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl unzip gnupg dumb-init jq locales tzdata \
      fonts-noto fonts-liberation fonts-dejavu-core \
      libnss3 libnss3-tools openssl \
      libasound2 libxss1 libgbm1 libx11-xcb1 \
      xvfb fluxbox wmctrl xsel pulseaudio; \
    echo "${LOCALE} UTF-8" > /etc/locale.gen; \
    locale-gen; \
    if [ "${ENABLE_VNC}" = "1" ]; then \
      apt-get install -y --no-install-recommends x11vnc websockify novnc; \
    fi; \
    rm -rf /var/lib/apt/lists/*

COPY scripts/install-chrome.sh /usr/local/bin/install-chrome
RUN chmod +x /usr/local/bin/install-chrome && \
    CHROME_VERSION="${CHROME_VERSION}" \
    CHROME_APT_PATTERN="${CHROME_APT_PATTERN}" \
    /usr/local/bin/install-chrome && \
    rm -rf /var/lib/apt/lists/*

COPY scripts/install-chromedriver.sh /usr/local/bin/install-chromedriver
RUN chmod +x /usr/local/bin/install-chromedriver && \
    /usr/local/bin/install-chromedriver "${DRIVER_VERSION}"

LABEL chrome.version="${CHROME_VERSION}" \
      chromedriver.version="${DRIVER_VERSION}"

COPY --from=devtools-builder /out/devtools /usr/local/bin/devtools
COPY --from=fileserver-builder /out/fileserver /usr/local/bin/fileserver
COPY --from=xseld-builder /out/xseld /usr/local/bin/xseld

RUN useradd -m -s /bin/bash selenium && \
    mkdir -p /home/selenium/.fluxbox /home/selenium/Downloads && \
    mkdir -p /etc/opt/chrome/policies/managed && \
    chown -R selenium:selenium /home/selenium /etc/opt/chrome || true && \
    mkdir -p /var/log && touch /var/log/vnc-stack.log && chown selenium:selenium /var/log/vnc-stack.log && \
    echo "cookie-file = ~/.config/pulse/cookie" >> /etc/pulse/client.conf

COPY fluxbox/init /home/selenium/.fluxbox/init
COPY fluxbox/apps /home/selenium/.fluxbox/apps
COPY chrome/policies.json /etc/opt/chrome/policies/managed/policies.json
RUN chown -R selenium:selenium /home/selenium/.fluxbox
RUN chown -R selenium:selenium /etc/opt/chrome/policies/managed

COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/xvfb-start.sh /usr/local/bin/xvfb-start
RUN chmod +x /entrypoint.sh /usr/local/bin/xvfb-start

USER selenium

EXPOSE 4444 5900 7900 7070 8080 9090

HEALTHCHECK --interval=20s --timeout=3s --retries=3 CMD curl -fsS http://127.0.0.1:4444/status || exit 1

ENTRYPOINT ["/usr/bin/dumb-init","--"]
CMD ["/entrypoint.sh"]
