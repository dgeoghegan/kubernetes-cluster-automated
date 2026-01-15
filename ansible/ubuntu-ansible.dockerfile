FROM ubuntu:24.04

RUN set -eux; \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get update -o Acquire::Retries=5; \
  apt-get install -y --no-install-recommends \
    python3 \
    python3-venv \
    python3-pip \
    sshpass \
    bash \
    ca-certificates; \
  python3 -m venv /opt/venv; \
  /opt/venv/bin/pip install --no-cache-dir --upgrade pip; \
  /opt/venv/bin/pip install --no-cache-dir ansible; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/*

  ENV PATH="/opt/venv/bin:${PATH}"
  WORKDIR /ansible
