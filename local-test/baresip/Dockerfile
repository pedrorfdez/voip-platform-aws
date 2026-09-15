# local-test/baresip/Dockerfile
# Build re + baresip from source. A source build makes sure that the
# aufile and g711 modules are available for file-based audio tests.
FROM debian:bookworm-slim AS build
RUN apt-get update -y && apt-get install -y --no-install-recommends \
      git build-essential cmake pkg-config ca-certificates \
      libssl-dev libsndfile1-dev \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
# re and baresip release together. Keep both tags equal.
ARG BARESIP_VERSION=v3.19.0
RUN git clone --depth 1 --branch "${BARESIP_VERSION}" https://github.com/baresip/re.git
RUN git clone --depth 1 --branch "${BARESIP_VERSION}" https://github.com/baresip/baresip.git
RUN cmake -S re -B re/build -DCMAKE_BUILD_TYPE=Release \
 && cmake --build re/build -j"$(nproc)" \
 && cmake --install re/build \
 && ldconfig
RUN cmake -S baresip -B baresip/build -DCMAKE_BUILD_TYPE=Release \
 && cmake --build baresip/build -j"$(nproc)" \
 && cmake --install baresip/build \
 && ldconfig

FROM debian:bookworm-slim
RUN apt-get update -y && apt-get install -y --no-install-recommends \
      libssl3 libsndfile1 sox gettext-base ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /usr/local /usr/local
RUN ldconfig
COPY accounts.template /templates/accounts.template
COPY config.template /templates/config.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
