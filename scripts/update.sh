#!/usr/bin/env bash

set -euo pipefail

CHANNELS_FILE="channels.nix"
DEFAULT_TAG="latest"
TAGS=(latest alpha beta native)

usage() {
    echo "Usage: $0 [--check | <version> | --all] [--tag <dist-tag>]"
    echo ""
    echo "Options:"
    echo "  --check        Check if a new version is available"
    echo "  <version>      Update to a specific version (e.g., 0.30.0)"
    echo "  --tag <tag>    Use npm dist-tag (e.g., latest, alpha, beta, native)"
    echo "  --all          Update all dist-tags (latest, alpha, beta, native)"
    echo ""
    echo "Examples:"
    echo "  $0 --check"
    echo "  $0 --check --tag alpha"
    echo "  $0 0.30.0"
    echo "  $0 0.87.0-alpha.1 --tag alpha"
    echo "  $0 --all"
    exit 1
}

get_current_version() {
    local tag="$1"
    perl -0777 -ne "if (/${tag}\\s*=\\s*\\{\\s*version\\s*=\\s*\\\"([^\\\"]+)\\\"/s) { print \"\$1\\n\"; }" "$CHANNELS_FILE"
}

get_latest_version() {
    local tag="$1"
    curl -s "https://registry.npmjs.org/@openai/codex/${tag}" | \
        sed -n 's/.*"version":"\([^"]*\)".*/\1/p'
}

sanitize_token() {
    # Keep only safe printable characters to avoid control bytes in channels.nix.
    printf '%s' "$1" | tr -cd 'A-Za-z0-9._-'
}

update_channel() {
    local tag="$1"
    local version="$2"
    local hash="$3"
    perl -0777 -i -pe "s/(${tag}\\s*=\\s*\\{\\s*version\\s*=\\s*\\\")[^\\\"]+(\\\";\\s*sha256\\s*=\\s*\\\")[^\\\"]+(\\\";)/\\\${1}${version}\\\${2}${hash}\\\${3}/s" "$CHANNELS_FILE"
}

TAG="$DEFAULT_TAG"
CHECK=false
ALL=false
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --tag)
            shift
            TAG="${1:-}"
            if [ -z "$TAG" ]; then
                echo "Error: --tag requires a value"
                usage
            fi
            shift
            ;;
        --check)
            CHECK=true
            shift
            ;;
        --all)
            ALL=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [ "$ALL" = true ] && [ ${#POSITIONAL[@]} -gt 0 ]; then
    echo "Error: --all cannot be combined with a specific version"
    usage
fi

if [ "$ALL" = true ] && [ "$CHECK" = true ] && [ ${#POSITIONAL[@]} -gt 0 ]; then
    usage
fi

if [ "$ALL" = false ] && [ "$CHECK" = false ] && [ ${#POSITIONAL[@]} -eq 0 ]; then
    usage
fi

if [ "$CHECK" = true ] && [ "$ALL" = false ]; then
    CURRENT_VERSION=$(get_current_version "$TAG")
    LATEST_VERSION=$(get_latest_version "$TAG")

    echo "Current version (${TAG}): $CURRENT_VERSION"
    echo "Latest version (${TAG}):  $LATEST_VERSION"

    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        echo "✅ Already up to date!"
        exit 0
    else
        echo "🆕 New version available: $LATEST_VERSION"
        echo "Run './scripts/update.sh $LATEST_VERSION --tag $TAG' to update"
        exit 1
    fi
fi

if [ "$CHECK" = true ] && [ "$ALL" = true ]; then
    UPDATE_NEEDED=false
    for tag in "${TAGS[@]}"; do
        CURRENT_VERSION=$(get_current_version "$tag")
        LATEST_VERSION=$(get_latest_version "$tag")
        echo "Current version (${tag}): $CURRENT_VERSION"
        echo "Latest version (${tag}):  $LATEST_VERSION"
        echo ""
        if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
            UPDATE_NEEDED=true
        fi
    done

    if [ "$UPDATE_NEEDED" = true ]; then
        echo "🆕 Updates available."
        exit 1
    fi

    echo "✅ Already up to date!"
    exit 0
fi

if [ "$ALL" = true ]; then
    UPDATED=false
    for tag in "${TAGS[@]}"; do
        CURRENT_VERSION=$(get_current_version "$tag")
        LATEST_VERSION=$(get_latest_version "$tag")
        LATEST_VERSION=$(sanitize_token "$LATEST_VERSION")

        if [ -z "$LATEST_VERSION" ]; then
            echo "Error: Could not fetch version for tag ${tag}"
            exit 1
        fi

        if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
            echo "✅ ${tag} already up to date (${CURRENT_VERSION})"
            continue
        fi

        echo "Updating ${tag} to version ${LATEST_VERSION}..."
        URL="https://registry.npmjs.org/@openai/codex/-/codex-${LATEST_VERSION}.tgz"
        HASH=$(nix-prefetch-url "$URL" 2>/dev/null || echo "")
        HASH=$(sanitize_token "$HASH")

        if [ -z "$HASH" ]; then
            echo "Error: Could not fetch hash for version $LATEST_VERSION (${tag})"
            exit 1
        fi

        echo "SHA256 (${tag}): $HASH"
        update_channel "$tag" "$LATEST_VERSION" "$HASH"
        UPDATED=true
    done

    if [ "$UPDATED" = false ]; then
        echo "✅ All channels already up to date!"
        exit 0
    fi
else
    VERSION="${POSITIONAL[0]}"

    if [ -z "$VERSION" ]; then
        usage
    fi

    echo "Updating ${TAG} to Codex CLI version $VERSION..."

    echo "Fetching SHA256 hash for version $VERSION..."
    VERSION=$(sanitize_token "$VERSION")
    URL="https://registry.npmjs.org/@openai/codex/-/codex-${VERSION}.tgz"
    HASH=$(nix-prefetch-url "$URL" 2>/dev/null || echo "")
    HASH=$(sanitize_token "$HASH")

    if [ -z "$HASH" ]; then
        echo "Error: Could not fetch hash for version $VERSION"
        echo "The package might not exist or the version might be incorrect"
        exit 1
    fi

    echo "SHA256 hash: $HASH"

    echo "Updating $CHANNELS_FILE..."
    update_channel "$TAG" "$VERSION" "$HASH"
fi

echo "Testing build..."
if nix build --no-link; then
    echo "✅ Build successful!"
    echo ""
    echo "✅ Channels updated successfully."
    echo "Don't forget to:"
    echo "  1. Test the new version: nix run . -- --version"
    echo "  2. Commit your changes"
    echo "  3. Push to GitHub"
else
    echo "❌ Build failed. Please check the error messages above."
    exit 1
fi
