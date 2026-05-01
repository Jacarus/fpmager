FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends libstdc++6 libgcc-s1 iproute2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Run `scripts\export_server.bat` first to produce these files.
COPY build/server/ .
COPY startup.sh .

RUN chmod +x fp-mager.x86_64 startup.sh

EXPOSE 24567/udp

CMD ["./startup.sh"]
