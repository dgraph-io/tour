# Private task to setup Darwin/macOS dependencies
_setup-darwin:
    #!/usr/bin/env bash
    [[ "$(uname)" == "Darwin" ]] || exit 0
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    if ! command -v hugo &> /dev/null; then
        echo "Installing hugo..."
        brew install hugo
    fi

# Private task to setup deps on debian derived linux distros.
_setup-linux-apt:
    #!/usr/bin/env bash
    $(command -v apt &> /dev/null) || exit 0
    $(command -v hugo &> /dev/null) || sudo apt install hugo

# Public task that runs platform-specific setup
setup: _setup-darwin _setup-linux-apt

# Run local development server with hot reload
dev: setup
    ./scripts/local.sh

# Build all branches for production
build: setup
    python3 scripts/build.py
