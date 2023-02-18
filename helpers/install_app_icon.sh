#!/bin/sh
#
# Helper script to generate and install favicons.
#
# Favicons are generated by `Real Favicon Generator`. See:
#   https://realfavicongenerator.net
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

WORKDIR=$(mktemp -d)

APP_ICON_URL=""
ICONS_DIR="/opt/noVNC/app/images/icons"
HTML_FILE="/opt/noVNC/index.html"
INSTALL_MISSING_TOOLS=1

usage() {
    if [ -n "$*" ]; then
        echo "$*"
        echo
    fi

    echo "usage: $(basename $0) ICON_URL [OPTIONS...]

Generate and install favicons.

Arguments:
  ICON_URL   URL pointing to the master picture, in PNG format.  All favicons are
             generated from this picture.

Options:
  --icons-dir         Directory where to put the generated icons.  Default: /opt/noVNC/app/images/icons
  --html-file         Path to the HTML file where to insert the HTML code.  Default: /opt/noVNC/index.html
  --no-tools-install  Do not automatically install missing tools.
"

    exit 1
}

die() {
    echo "Failed to generate favicons: $*."
    exit 1
}

install_build_dependencies_alpine() {
    INSTALLED_PKGS=""
    if [ -z "$(which curl)" ]; then
        INSTALLED_PKGS="$INSTALLED_PKGS curl"
    fi
    if [ -z "$(which jq)" ]; then
        INSTALLED_PKGS="$INSTALLED_PKGS jq"
    fi
    if [ -z "$(which sed)" ] || ! sed --version | grep -q "(GNU sed)"; then
        INSTALLED_PKGS="$INSTALLED_PKGS sed"
    fi

    if [ -n "$INSTALLED_PKGS" ]; then
        add-pkg --virtual rfg-build-dependencies $INSTALLED_PKGS
    fi
}

install_build_dependencies_debian() {
    INSTALLED_PKGS=""
    if [ -z "$(which curl)" ]; then
        INSTALLED_PKGS="$INSTALLED_PKGS curl ca-certificates"
    fi
    if [ -z "$(which jq)" ]; then
        INSTALLED_PKGS="$INSTALLED_PKGS jq"
    fi
    if [ -z "$(which unzip)" ]; then
        INSTALLED_PKGS="$INSTALLED_PKGS unzip"
    fi

    if [ -n "$INSTALLED_PKGS" ]; then
        add-pkg --virtual rfg-build-dependencies $INSTALLED_PKGS
    fi
}

install_build_dependencies() {
    if [ "$INSTALL_MISSING_TOOLS" -eq 1 ]; then
        if [ -n "$(which apk)" ]; then
            install_build_dependencies_alpine
        else
            install_build_dependencies_debian
        fi
    fi
}

uninstall_build_dependencies() {
    if [ "$INSTALL_MISSING_TOOLS" -eq 1 ]; then
        if [ -n "$INSTALLED_PKGS" ]; then
            del-pkg rfg-build-dependencies
        fi
    fi
}

cleanup() {
    rm -rf "$WORKDIR"
}

# Parse arguments.
while [ "$#" -ne 0 ]
do
    case "$1" in
        --icons-dir)
            ICONS_DIR="${2:-}"
            if [ -z "$ICONS_DIR" ]; then
                usage "Icons directory missing."
            fi
            shift 2
            ;;
        --html-file)
            HTML_FILE="${2:-}"
            if [ -z "$HTML_FILE" ]; then
                usage "HTML file path  missing."
            fi
            shift 2
            ;;
        --no-tools-install)
            INSTALL_MISSING_TOOLS=0
            shift
            ;;
        -h|--help)
            usage
            ;;
        --*)
            usage "Unknown argument \"$1\"."
            ;;
        *)
            if [ -z "$APP_ICON_URL"]; then
                APP_ICON_URL="$1"
                shift
            else
                usage "Unknown argument \"$1\"."
            fi
            ;;
    esac
done

[ -n "$APP_ICON_URL" ] || usage "Icon URL is missing."

# Check if URL is pointing to a local file.
if [ -f "$APP_ICON_URL" ]; then
    ICON_URL_IS_LOCAL_PATH=true
elif [ "${APP_ICON_URL#file://}" != "$APP_ICON_URL" ]; then
    ICON_URL_IS_LOCAL_PATH=true
    APP_ICON_URL="${APP_ICON_URL#file://}"
    if [ ! -f "$APP_ICON_URL" ]; then
        die "$APP_ICON_URL: no such file"
    fi
else
    ICON_URL_IS_LOCAL_PATH=false
fi

echo "Installing dependencies..."
install_build_dependencies

# Clear any previously generated icons.
rm -rf "$ICONS_DIR"
mkdir -p "$ICONS_DIR"

# Download the master icon.
if $ICON_URL_IS_LOCAL_PATH; then
    cp "$APP_ICON_URL" "$ICONS_DIR"/master_icon.png
else
    curl -sS -L -o "$ICONS_DIR"/master_icon.png "$APP_ICON_URL"
fi

# Create the description file.
cat <<EOF > "$WORKDIR"/faviconDescription.json
{
  "favicon_generation": {
    "api_key": "402333a17311c9aa68257b9c5fc571276090ee56",
    "master_picture": {
EOF
if $ICON_URL_IS_LOCAL_PATH; then
cat <<EOF >> "$WORKDIR"/faviconDescription.json
      "type": "inline",
      "content": "$(base64 -w 0 "$APP_ICON_URL")"
EOF
else
cat <<EOF >> "$WORKDIR"/faviconDescription.json
      "type": "url",
      "url": "$APP_ICON_URL"
EOF
fi
cat <<EOF >> "$WORKDIR"/faviconDescription.json
    },
    "files_location": {
      "type": "root"
    },
    "favicon_design": {
      "desktop_browser": {},
      "ios": {
        "picture_aspect": "background_and_margin",
        "margin": "14%",
        "background_color": "#ffffff",
        "assets": {
          "ios6_and_prior_icons": false,
          "ios7_and_later_icons": true,
          "precomposed_icons": false,
          "declare_only_default_icon": true
        }
      },
      "windows": {
        "picture_aspect": "no_change",
        "background_color": "#2d89ef",
        "assets": {
          "windows_80_ie_10_tile": false,
          "windows_10_ie_11_edge_tiles": {
            "small": false,
            "medium": true,
            "big": false,
            "rectangle": false
          }
        }
      },
      "android_chrome": {
        "picture_aspect": "no_change",
        "manifest": {
          "display": "standalone"
        },
        "assets": {
          "legacy_icon": false,
          "low_resolution_icons": false
        },
        "theme_color": "#ffffff"
      },
      "safari_pinned_tab": {
        "picture_aspect": "silhouette",
        "theme_color": "#5bbad5"
      }
    },
    "settings": {
      "scaling_algorithm": "Mitchell",
      "error_on_image_too_small": true
    },
    "versioning": {
      "param_name": "v",
      "param_value": "$(date | md5sum | cut -c1-10)"
    }
  }
}
EOF

echo "Generating favicons..."
curl -sS -L -X POST -d@"$WORKDIR"/faviconDescription.json https://realfavicongenerator.net/api/favicon > "$WORKDIR"/faviconData.json

RESULT="$(jq --raw-output '.favicon_generation_result.result.status' < "$WORKDIR"/faviconData.json)"
case "$RESULT" in
    success) ;;
    error)
        ERROR_MESSAGE="$(jq --raw-output '.favicon_generation_result.result.error_message' < "$WORKDIR"/faviconData.json)"
        die "$ERROR_MESSAGE"
        ;;
    *)
        die "Unexpected result: $RESULT"
        ;;
esac

echo "Downloading icons package..."
PACKAGE_URL="$(jq --raw-output '.favicon_generation_result.favicon.package_url' < "$WORKDIR"/faviconData.json)"
if [ -z "$PACKAGE_URL" ] || [ "$PACKAGE_URL" = "null" ]; then
    die "Package URL not provided"
else
    curl -sS -L -o "$WORKDIR"/package.zip "$PACKAGE_URL"
fi

echo "Extracting icons package..."
unzip "$WORKDIR"/package.zip -d "$ICONS_DIR"

echo "Adjusting HTML page..."
jq -r '.favicon_generation_result.favicon.html_code' "$WORKDIR"/faviconData.json > "$WORKDIR"/htmlCode
if [ "$(cat "$WORKDIR"/htmlCode)" = "null" ]; then
    die "HTML code not found"
else
    sed -i 's/^/    /' "$WORKDIR"/htmlCode
    sed -i 's|href="/|href="|' "$WORKDIR"/htmlCode
fi
cat "$HTML_FILE" | sed -ne "/<!-- BEGIN Favicons -->/ {p; r $WORKDIR/htmlCode" -e ":a; n; /<!-- END Favicons -->/ {p; b}; ba}; p" > "$WORKDIR"/tmp.html
if diff "$WORKDIR"/tmp.html "$HTML_FILE" > /dev/null 2>&1; then
    die "Could not insert HTML code."
fi
mv "$WORKDIR"/tmp.html "$HTML_FILE"

echo "Removing dependencies..."
uninstall_build_dependencies

echo "Cleaning..."
cleanup

echo "Favicons successfully generated."

# vim:ft=sh:ts=4:sw=4:et:sts=4
