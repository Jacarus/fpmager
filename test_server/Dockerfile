FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends iptables iproute2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY test_server/udp_echo.py .

EXPOSE 24567/udp

CMD ["python3", "-u", "udp_echo.py"]
