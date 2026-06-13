# Reproducible build environment for Vitals (Linux). Mirrors the CI image so a
# green `swift build` here means a green build in GitHub Actions.
#
#   docker build -t vitals-linux apps/desktop-linux
#   docker run --rm -v "$PWD":/src -w /src/apps/desktop-linux vitals-linux ./build.sh
FROM swift:6.0-noble

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      pkg-config \
      libgtk-4-dev \
      libadwaita-1-dev \
      libcairo2-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
