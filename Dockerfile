FROM alpine:latest

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    wget \
    git

# Install Hugo (standard version - extended requires glibc)
RUN wget -qO- https://github.com/gohugoio/hugo/releases/download/v0.139.0/hugo_0.139.0_linux-amd64.tar.gz \
    | tar xz -C /usr/local/bin hugo

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Create docker directory for dgraph data mount compatibility
RUN mkdir -p /app/docker/dgraph

# Copy entrypoint script and make it executable
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose Hugo port
EXPOSE 1313

# Set default environment variables for in-cluster addresses
ENV DGRAPH_ALPHA=http://tour-dgraph:8080
ENV HUGO_PORT=1313

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["server"]
