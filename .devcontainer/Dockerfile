FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update \
    && apt-get install --no-install-recommends --yes \
        bash \
        bats \
        ca-certificates \
        curl \
        git \
        jq \
        just \
        nodejs \
        npm \
        shellcheck \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --no-cache-dir git-filter-repo==2.47.0 PyYAML==6.0.2

WORKDIR /workspace
CMD ["bash"]
