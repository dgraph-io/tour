# =============================================================================
# Base stage with common dependencies
# =============================================================================
FROM alpine:latest AS base

# Install base dependencies
RUN apk add --no-cache \
    bash \
    curl \
    git \
    jq \
    make \
    wget

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Create docker directory for dgraph data mount compatibility
RUN mkdir -p /app/docker/dgraph

# Set default environment variables
ENV DGRAPH_ALPHA=http://tour-dgraph:8080
ENV HUGO_PORT=1313

# =============================================================================
# tour-hugo: Hugo server for the tour site
# =============================================================================
FROM base AS tour-hugo

# Install Hugo (standard version - extended requires glibc)
ARG TARGETARCH
RUN HUGO_VERSION="0.139.0" && \
    case "${TARGETARCH}" in \
        arm64) HUGO_ARCH="arm64" ;; \
        *) HUGO_ARCH="amd64" ;; \
    esac && \
    wget -qO- "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_linux-${HUGO_ARCH}.tar.gz" \
    | tar xz -C /usr/local/bin hugo

# Copy entrypoint script and make it executable
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose Hugo port
EXPOSE 1313

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["server"]

# =============================================================================
# tour-seed: Full dev environment with all dependencies
# =============================================================================
FROM base AS tour-seed

# Set Dgraph connection to use internal Docker hostname
ENV DGRAPH_ALPHA=http://tour-dgraph:8080

# Install Hugo (standard version - extended requires glibc)
ARG TARGETARCH
RUN HUGO_VERSION="0.139.0" && \
    case "${TARGETARCH}" in \
        arm64) HUGO_ARCH="arm64" ;; \
        *) HUGO_ARCH="amd64" ;; \
    esac && \
    wget -qO- "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_linux-${HUGO_ARCH}.tar.gz" \
    | tar xz -C /usr/local/bin hugo

# Install additional dev dependencies (matches make deps-dev)
RUN apk add --no-cache \
    nodejs \
    npm && \
    npm install -g npx

# Install glibc compatibility for dgraph binary
RUN apk add --no-cache gcompat

# Install Dgraph CLI for running dgraph live loader
ARG TARGETARCH
RUN DGRAPH_VERSION="25.1.0" && \
    case "${TARGETARCH}" in \
        arm64) DGRAPH_ARCH="arm64" ;; \
        *) DGRAPH_ARCH="amd64" ;; \
    esac && \
    wget -qO- "https://github.com/dgraph-io/dgraph/releases/download/v${DGRAPH_VERSION}/dgraph-linux-${DGRAPH_ARCH}.tar.gz" \
    | tar xz -C /usr/local/bin

# Run make deps-dev
RUN make deps-dev

# Keep container running
CMD ["tail", "-f", "/dev/null"]
