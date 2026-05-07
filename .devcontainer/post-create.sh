#!/usr/bin/env bash
# Dev container post-create.
# Installs everything we don't (or can't reliably) install via features,
# then prints versions of every tool `azd up` invokes — so a missing
# toolchain shows up here instead of mid-deploy.
set -euo pipefail

ARCH="$(dpkg --print-architecture)"     # arm64 | amd64
UBUNTU_CODENAME="$(lsb_release -cs)"

# --- Microsoft package signing key + apt repo ----------------------------
if [ ! -f /etc/apt/trusted.gpg.d/microsoft.gpg ]; then
  echo "Adding Microsoft apt repo..."
  curl -sLS https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor \
    | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg >/dev/null
  echo "deb [arch=${ARCH}] https://packages.microsoft.com/repos/microsoft-ubuntu-${UBUNTU_CODENAME}-prod ${UBUNTU_CODENAME} main" \
    | sudo tee /etc/apt/sources.list.d/microsoft-prod.list >/dev/null
  sudo apt-get update -qq
fi

# --- .NET 10 SDK ---------------------------------------------------------
# We install via Microsoft's dotnet-install.sh because the apt repo doesn't
# always carry preview/.0 channels for arm64. Retry up to 3 times — the
# aka.ms CDN occasionally 5xxs on first hit.
if ! command -v dotnet >/dev/null 2>&1 || ! dotnet --list-sdks | grep -q '^10\.'; then
  echo "Installing .NET 10 SDK..."
  curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  chmod +x /tmp/dotnet-install.sh
  for i in 1 2 3; do
    if sudo /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet; then
      break
    fi
    echo "dotnet-install attempt $i failed, retrying in 10s..."
    sleep 10
  done
  sudo ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
fi

# --- Azure Functions Core Tools v4 --------------------------------------
if ! command -v func >/dev/null 2>&1; then
  echo "Installing Azure Functions Core Tools v4..."
  sudo apt-get install -y azure-functions-core-tools-4
fi

# --- Azure Static Web Apps CLI ------------------------------------------
# The Node feature sets a user-writable npm global prefix, so no sudo.
if ! command -v swa >/dev/null 2>&1; then
  echo "Installing Azure Static Web Apps CLI..."
  npm install -g --silent @azure/static-web-apps-cli
fi

# --- Sanity check --------------------------------------------------------
echo
echo "=== Tool versions ==="
azd version
az --version | head -n 1
node --version
npm --version
python3 --version
dotnet --version
func --version
swa --version
gh --version | head -n 1
