# local-test/sipp/Dockerfile
FROM debian:bookworm-slim
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends sip-tester \
 && rm -rf /var/lib/apt/lists/*
COPY scripts/sipp /sipp
ENTRYPOINT ["sipp"]
