#!/usr/bin/env bash
# Universal manual ionCube Loader installer for Linux
# Version: 2.0.3
#
# Goals:
#   - Discover multiple PHP installations on common hosting/control-panel stacks.
#   - Interactive PHP selection (Enter = all discovered PHP installations).
#   - Interactive ionCube version selection (Enter = latest production release).
#   - Download current official loaders, or requested historical loaders.
#   - Historical lookup order: ionCube historical CDN patterns, then known repo metadata.
#   - Preflight every loader against the exact PHP binary before changing config.
#   - Back up every modified PHP config file.
#   - Handle CloudLinux CageFS when present, but do not require CloudLinux.
#   - Recycle/reload common PHP handlers/web stacks after a successful change.
#
# Tested design targets:
#   cPanel EA-PHP, CloudLinux CageFS, CloudLinux ALT-PHP (existing ionCube module),
#   Plesk PHP, DirectAdmin CustomBuild PHP, Debian/Ubuntu PHP, RHEL-family PHP,
#   Remi PHP, LiteSpeed/OpenLiteSpeed LSPHP, PHP-FPM, Apache/mod_php, CGI/suPHP.
#
# IMPORTANT:
#   No installer can safely guarantee every custom PHP build or custom per-domain php.ini.
#   This script detects known layouts and falls back to `php --ini`. It refuses ambiguous
#   ionCube configuration instead of guessing.

set -Eeuo pipefail

SCRIPT_VERSION="2.0.3"
BASE_DIR="/usr/local/ioncube-universal"
LOADERS_DIR="${BASE_DIR}/loaders"
DOWNLOAD_DIR="${BASE_DIR}/downloads"
BACKUP_ROOT="/var/backups/ioncube-universal"
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/ioncube-universal-$(date +%Y%m%d-%H%M%S).log"
CAGE_CFG="/etc/cagefs/conf.d/ioncube-universal.cfg"
OFFICIAL_RELEASE_FEED="https://www.ioncube.com/feeds/product_info/versions.php?format=json&item=loader-release-dates"
SLACKBUILDS_PAGES=(
  "https://slackbuilds.org/repository/15.0/development/ioncube-loader/"
  "https://slackbuilds.org/repository/14.2/development/ioncube-loader/"
  "https://slackbuilds.org/repository/14.1/development/ioncube-loader/"
)

AUTO_YES=0
STATUS_ONLY=0
DRY_RUN=0
NO_RESTART=0
PHP_SPEC=""
REQUESTED_VERSION=""
VERIFY_USER=""
CUSTOM_SOURCE_URL=""
ALLOW_THIRD_PARTY=0

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi

_ts() { date '+%H:%M:%S'; }
info() { printf '%s[%s] INFO %s%s\n' "$C_CYAN" "$(_ts)" "$*" "$C_RESET"; }
ok()   { printf '%s[%s] OK   %s%s\n' "$C_GREEN" "$(_ts)" "$*" "$C_RESET"; }
warn() { printf '%s[%s] WARN %s%s\n' "$C_YELLOW" "$(_ts)" "$*" "$C_RESET"; }
fail() { printf '%s[%s] FAIL %s%s\n' "$C_RED" "$(_ts)" "$*" "$C_RESET" >&2; }
section() { printf '\n%s%s== %s ==%s\n' "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"; }

usage() {
cat <<'USAGE'
Usage:
  ioncube-universal-installer.sh [options]

Options:
  --status                    Detect PHP installations and show current ionCube only.
  --php=8.2,8.3               Select PHP version(s). A numeric discovered ID is also accepted.
                              If omitted interactively, Enter selects all detected PHP versions.
  --ioncube-version=15.5.0    Install this exact ionCube Loader release.
  --ioncube-version=latest    Install the current production Loader (default on Enter).
  --source-url=URL            Use an explicit loader tar.gz URL (advanced/fallback).
  --allow-third-party         Allow a non-ioncube.com source without an interactive prompt.
  --verify-user=USER          If CageFS exists, verify selected PHP binaries inside USER's CageFS.
  --dry-run                   Download/preflight/show the plan, but do not modify the server.
  --no-restart                Do not recycle/reload PHP/web workers after configuration changes.
  --yes, -y                   Non-interactive confirmation. Missing choices default to all + latest.
  --help, -h                  Show this help.

Examples:
  ./ioncube-universal-installer.sh
  ./ioncube-universal-installer.sh --status
  ./ioncube-universal-installer.sh --php=8.2,8.3 --ioncube-version=15.5.0
  ./ioncube-universal-installer.sh --php=8.3 --ioncube-version=latest --yes
  ./ioncube-universal-installer.sh --php=8.3 --dry-run
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --status) STATUS_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --no-restart) NO_RESTART=1 ;;
    --yes|-y) AUTO_YES=1 ;;
    --allow-third-party) ALLOW_THIRD_PARTY=1 ;;
    --php=*) PHP_SPEC="${arg#*=}" ;;
    --ioncube-version=*) REQUESTED_VERSION="${arg#*=}" ;;
    --verify-user=*) VERIFY_USER="${arg#*=}" ;;
    --source-url=*) CUSTOM_SOURCE_URL="${arg#*=}" ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Unknown option: $arg"; usage; exit 2 ;;
  esac
done

if (( EUID != 0 )); then
  fail "Run this script as root."
  exit 1
fi

mkdir -p "$LOG_DIR" "$BACKUP_ROOT" "$BASE_DIR" "$LOADERS_DIR" "$DOWNLOAD_DIR"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'rc=$?; fail "Stopped at line ${BASH_LINENO[0]} (exit ${rc}). Log: ${LOG_FILE}"; exit "$rc"' ERR

command_exists() { command -v "$1" >/dev/null 2>&1; }
real_path() { readlink -f "$1" 2>/dev/null || printf '%s\n' "$1"; }

extract_ioncube_version() {
  sed -nE 's/.*ionCube PHP Loader( \+ ionCube24)? v([0-9]+(\.[0-9]+)+).*/\2/p' | head -n1
}

current_loader_version() {
  local bin="$1" out v
  [[ -x "$bin" ]] || { printf '%s' "-"; return 0; }
  out="$($bin -v 2>&1 || true)"
  v="$(printf '%s\n' "$out" | extract_ioncube_version)"
  [[ -n "$v" ]] && printf '%s' "$v" || printf '%s' "none"
}

version_cmp() {
  # prints: -1 if a<b, 0 if equal, 1 if a>b
  local a="$1" b="$2" top
  [[ "$a" == "$b" ]] && { printf '0'; return; }
  top="$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n1)"
  [[ "$top" == "$a" ]] && printf '1' || printf '%s' '-1'
}

sanitize_slug() { printf '%s' "$1" | sed 's#[^A-Za-z0-9._-]#_#g'; }

os_name="unknown"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  os_name="${PRETTY_NAME:-${NAME:-unknown}}"
fi

panels=()
[[ -d /usr/local/cpanel ]] && panels+=("cPanel")
command_exists plesk && panels+=("Plesk")
[[ -d /usr/local/directadmin ]] && panels+=("DirectAdmin")
(( ${#panels[@]} == 0 )) && panels+=("none/unknown")

cloudlinux_os="No"
[[ -r /etc/cloudlinux-release || -d /opt/cloudlinux ]] && cloudlinux_os="Yes"
cagefs_state="No"
command_exists cagefsctl && cagefs_state="Yes"

webs=()
[[ -d /usr/local/lsws ]] && webs+=("LiteSpeed/OpenLiteSpeed")
pgrep -x nginx >/dev/null 2>&1 && webs+=("Nginx")
{ pgrep -x httpd >/dev/null 2>&1 || pgrep -x apache2 >/dev/null 2>&1; } && webs+=("Apache")
(( ${#webs[@]} == 0 )) && webs+=("not detected")

section "Environment"
printf 'Script version : %s\n' "$SCRIPT_VERSION"
printf 'OS             : %s\n' "$os_name"
printf 'Kernel         : %s\n' "$(uname -r)"
printf 'Architecture   : %s\n' "$(uname -m)"
printf 'Control panel  : %s\n' "$(IFS=', '; echo "${panels[*]}")"
printf 'CloudLinux OS  : %s\n' "$cloudlinux_os"
printf 'CageFS         : %s\n' "$cagefs_state"
printf 'Web stack      : %s\n' "$(IFS=', '; echo "${webs[*]}")"
printf 'Log            : %s\n' "$LOG_FILE"

# ---------- PHP discovery ----------
declare -a PHP_BIN=() PHP_REAL=() PHP_FAMILY=() PHP_FULL=() PHP_DOT=() PHP_ZTS=() PHP_PLATFORM=() PHP_CURRENT=() PHP_CONTEXTS=() PHP_SLUG=() PHP_SELECTED=()

declare -A SEEN_BIN=()

family_for_path() {
  local p="$1"
  case "$p" in
    /opt/cpanel/ea-php*/root/usr/bin/php) echo "cPanel EA-PHP" ;;
    /opt/alt/php*/usr/bin/php) echo "CloudLinux ALT-PHP" ;;
    /opt/plesk/php/*/bin/php) echo "Plesk PHP" ;;
    /opt/remi/php*/root/usr/bin/php) echo "Remi PHP" ;;
    /opt/rh/*/root/usr/bin/php) echo "SCL PHP" ;;
    /usr/local/directadmin/*) echo "DirectAdmin PHP" ;;
    /usr/local/php*/bin/php) echo "DirectAdmin/local PHP" ;;
    /usr/local/lsws/lsphp*/bin/lsphp) echo "LiteSpeed LSPHP" ;;
    /usr/bin/php*|/bin/php*) echo "System PHP" ;;
    *) echo "Custom PHP" ;;
  esac
}

platform_for_binary() {
  local bin="$1" desc lddout musl=0
  desc="$(file -Lb "$bin" 2>/dev/null || true)"
  lddout="$(ldd "$bin" 2>&1 || true)"
  if printf '%s\n%s\n' "$lddout" "$desc" | grep -qi musl; then
    musl=1
  fi
  case "$desc" in
    *x86-64*|*x86_64*)
      (( musl == 1 )) && echo "x86_64-musl" || echo "x86_64-glibc" ;;
    *80386*|*i386*|*i686*) echo "x86-glibc" ;;
    *aarch64*|*ARM64*) echo "aarch64-glibc" ;;
    *ARM*) echo "armv7l-glibc" ;;
    *)
      case "$(uname -m)" in
        x86_64|amd64) (( musl == 1 )) && echo "x86_64-musl" || echo "x86_64-glibc" ;;
        i?86) echo "x86-glibc" ;;
        aarch64|arm64) echo "aarch64-glibc" ;;
        armv7l) echo "armv7l-glibc" ;;
        *) echo "unsupported" ;;
      esac
      ;;
  esac
}

append_context() {
  local idx="$1" ini="$2" dir="$3" label="$4"
  [[ "$ini" == "(none)" || "$ini" == "none" ]] && ini=""
  [[ "$dir" == "(none)" || "$dir" == "none" ]] && dir=""
  PHP_CONTEXTS[$idx]+="${ini}|${dir}|${label}"$'\n'
  return 0
}

append_runtime_context_from_binary() {
  local idx="$1" hb="$2" label="$3" out loaded scan
  [[ -x "$hb" ]] || return 0
  if [[ "$(basename "$hb")" == "php-fpm" || "$(basename "$hb")" == php-fpm* ]]; then
    out="$($hb -i 2>/dev/null || true)"
    loaded="$(printf '%s\n' "$out" | sed -n 's/^Loaded Configuration File =>[[:space:]]*//p' | head -n1)"
    scan="$(printf '%s\n' "$out" | sed -n 's/^Scan this dir for additional .ini files =>[[:space:]]*//p' | head -n1)"
  else
    out="$($hb --ini 2>/dev/null || true)"
    loaded="$(printf '%s\n' "$out" | sed -n 's/^Loaded Configuration File:[[:space:]]*//p' | head -n1)"
    scan="$(printf '%s\n' "$out" | sed -n 's/^Scan for additional .ini files in:[[:space:]]*//p' | head -n1)"
  fi
  if [[ -n "$loaded$scan" ]]; then
    append_context "$idx" "$loaded" "$scan" "$label"
  fi
  # Optional SAPI ini discovery may legitimately yield nothing.
  return 0
}

collect_contexts() {
  local idx="$1" bin="${PHP_BIN[$1]}" fam="${PHP_FAMILY[$1]}" dot="${PHP_DOT[$1]}"
  local iniout loaded scan p root key prefix sapidir
  iniout="$($bin --ini 2>/dev/null || true)"
  loaded="$(printf '%s\n' "$iniout" | sed -n 's/^Loaded Configuration File:[[:space:]]*//p' | head -n1)"
  scan="$(printf '%s\n' "$iniout" | sed -n 's/^Scan for additional .ini files in:[[:space:]]*//p' | head -n1)"

  # ALT-PHP php.d is generated by PHP Selector; prefer canonical php.d.all.
  if [[ "$fam" != "CloudLinux ALT-PHP" ]]; then
    append_context "$idx" "$loaded" "$scan" "CLI/runtime"
    local bindir="$(dirname "$bin")"
    append_runtime_context_from_binary "$idx" "$bindir/php-cgi" "CGI runtime"
    append_runtime_context_from_binary "$idx" "$bindir/php-fpm" "FPM runtime"
    append_runtime_context_from_binary "$idx" "$bindir/lsphp" "LSAPI runtime"
  fi

  case "$bin" in
    /opt/cpanel/ea-php*/root/usr/bin/php)
      root="${bin%/usr/bin/php}"
      append_context "$idx" "$root/etc/php.ini" "$root/etc/php.d" "cPanel EA-PHP"
      ;;
    /opt/alt/php*/usr/bin/php)
      root="${bin%/usr/bin/php}"
      append_context "$idx" "$root/etc/php.ini" "$root/etc/php.d.all" "CloudLinux ALT-PHP canonical"
      ;;
    /opt/plesk/php/*/bin/php)
      root="${bin%/bin/php}"
      append_context "$idx" "$root/etc/php.ini" "$root/etc/php.d" "Plesk"
      ;;
    /opt/remi/php*/root/usr/bin/php)
      key="$(printf '%s' "$bin" | sed -n 's#^/opt/remi/\(php[0-9][0-9]\)/root/usr/bin/php$#\1#p')"
      [[ -n "$key" ]] && append_context "$idx" "/etc/opt/remi/$key/php.ini" "/etc/opt/remi/$key/php.d" "Remi"
      ;;
    /usr/local/php*/bin/php)
      prefix="${bin%/bin/php}"
      append_context "$idx" "$prefix/lib/php.ini" "$prefix/lib/php.conf.d" "DirectAdmin/local"
      ;;
  esac

  # Debian/Ubuntu keep separate config trees per SAPI.
  if [[ -d "/etc/php/$dot" ]]; then
    for sapidir in /etc/php/"$dot"/*; do
      [[ -d "$sapidir" ]] || continue
      [[ -f "$sapidir/php.ini" || -d "$sapidir/conf.d" ]] || continue
      append_context "$idx" "$sapidir/php.ini" "$sapidir/conf.d" "Debian SAPI $(basename "$sapidir")"
    done
  fi

  # Conventional system PHP layout.
  if [[ "$fam" == "System PHP" && ( -f /etc/php.ini || -d /etc/php.d ) ]]; then
    append_context "$idx" "/etc/php.ini" "/etc/php.d" "System"
  fi
  return 0
}

add_php_candidate() {
  local bin="$1" real full dot zts fam platform idx sig bindesc
  [[ -x "$bin" ]] || return 0
  if [[ "$bin" == "/usr/local/bin/php" && -d /usr/local/cpanel ]]; then
    bindesc="$(file -Lb "$bin" 2>/dev/null || true)"
    [[ "$bindesc" == *ELF* ]] || return 0
  fi
  real="$(real_path "$bin")"
  [[ -n "${SEEN_BIN[$real]:-}" ]] && return 0

  full="$($bin -n -r 'echo PHP_VERSION;' 2>/dev/null || true)"
  [[ "$full" =~ ^[0-9]+\.[0-9]+ ]] || return 0
  dot="$($bin -n -r 'echo PHP_MAJOR_VERSION,".",PHP_MINOR_VERSION;' 2>/dev/null || true)"
  zts="$($bin -n -r 'echo PHP_ZTS ? "ts" : "nts";' 2>/dev/null || true)"
  [[ -n "$dot" ]] || return 0

  SEEN_BIN[$real]=1
  fam="$(family_for_path "$bin")"
  platform="$(platform_for_binary "$real")"
  idx="${#PHP_BIN[@]}"
  PHP_BIN[$idx]="$bin"
  PHP_REAL[$idx]="$real"
  PHP_FAMILY[$idx]="$fam"
  PHP_FULL[$idx]="$full"
  PHP_DOT[$idx]="$dot"
  PHP_ZTS[$idx]="${zts:-nts}"
  PHP_PLATFORM[$idx]="$platform"
  PHP_CURRENT[$idx]="$(current_loader_version "$bin")"
  PHP_CONTEXTS[$idx]=""
  sig="$(printf '%s' "$real" | sha256sum | awk '{print substr($1,1,10)}')"
  PHP_SLUG[$idx]="$(sanitize_slug "${fam}-${dot}-${sig}")"
  PHP_SELECTED[$idx]=0
  if ! collect_contexts "$idx"; then
    warn "Could not fully inspect PHP configuration contexts for: $bin"
    PHP_CONTEXTS[$idx]=""
  fi
  return 0
}

shopt -s nullglob
candidates=(
  /opt/cpanel/ea-php*/root/usr/bin/php
  /opt/alt/php*/usr/bin/php
  /opt/plesk/php/*/bin/php
  /opt/remi/php*/root/usr/bin/php
  /opt/rh/*/root/usr/bin/php
  /usr/local/php*/bin/php
  /usr/local/lsws/lsphp*/bin/lsphp
  /usr/bin/php
  /usr/bin/php[0-9].[0-9]
  /usr/bin/php[0-9][0-9]
  /usr/local/bin/php
)
if command_exists php; then candidates+=("$(command -v php)"); fi
for p in "${candidates[@]}"; do
  # Ignore CloudLinux special/internal PHP trees, e.g. php74-imunify.
  case "$p" in
    /opt/alt/php*/usr/bin/php)
      [[ "$p" =~ ^/opt/alt/php[0-9]{2}/usr/bin/php$ ]] || continue
      ;;
  esac
  if ! add_php_candidate "$p"; then

    warn "Skipping PHP candidate after discovery error: $p"
  fi
done
shopt -u nullglob

if (( ${#PHP_BIN[@]} == 0 )); then
  fail "No usable PHP CLI/LSPHP binary was discovered."
  exit 1
fi

handler_summary() {
  local idx="$1" base d out="" b v
  base="$(dirname "${PHP_BIN[$idx]}")"
  for b in "$base/php-cgi" "$base/php-fpm" "$base/lsphp"; do
    [[ -x "$b" ]] || continue
    [[ "$(real_path "$b")" == "${PHP_REAL[$idx]}" ]] && continue
    v="$(current_loader_version "$b")"
    case "$(basename "$b")" in
      php-cgi) out+="cgi=$v " ;;
      php-fpm) out+="fpm=$v " ;;
      lsphp) out+="lsapi=$v " ;;
    esac
  done
  printf '%s' "${out% }"
}

show_php_status() {
  section "$1"
  printf '%-4s %-8s %-21s %-10s %-12s %-16s %s\n' "ID" "PHP" "Family" "ionCube" "Platform" "Other SAPIs" "Binary"
  printf '%-4s %-8s %-21s %-10s %-12s %-16s %s\n' "--" "--------" "---------------------" "----------" "------------" "----------------" "------"
  local i hs
  for ((i=0; i<${#PHP_BIN[@]}; i++)); do
    hs="$(handler_summary "$i")"
    printf '%-4s %-8s %-21s %-10s %-12s %-16s %s\n' \
      "$((i+1))" "${PHP_FULL[$i]}" "${PHP_FAMILY[$i]}" "${PHP_CURRENT[$i]}" "${PHP_PLATFORM[$i]}" "${hs:--}" "${PHP_BIN[$i]}"
  done
}

show_php_status "Detected PHP installations"

if (( STATUS_ONLY == 1 )); then
  ok "Status-only mode complete."
  exit 0
fi

# ---------- interactive PHP selection ----------
select_php_by_spec() {
  local spec="$1" token i found any=0
  for ((i=0; i<${#PHP_SELECTED[@]}; i++)); do PHP_SELECTED[$i]=0; done
  if [[ -z "$spec" || "$spec" == "all" || "$spec" == "*" ]]; then
    for ((i=0; i<${#PHP_SELECTED[@]}; i++)); do PHP_SELECTED[$i]=1; done
    return 0
  fi
  IFS=',' read -r -a toks <<< "$spec"
  for token in "${toks[@]}"; do
    token="$(printf '%s' "$token" | xargs)"
    [[ -n "$token" ]] || continue
    found=0
    if [[ "$token" =~ ^[0-9]+$ ]] && (( token >= 1 && token <= ${#PHP_BIN[@]} )); then
      PHP_SELECTED[$((token-1))]=1; found=1; any=1
    fi
    for ((i=0; i<${#PHP_BIN[@]}; i++)); do
      if [[ "$token" == "${PHP_DOT[$i]}" || "$token" == "${PHP_FULL[$i]}" ]]; then
        PHP_SELECTED[$i]=1; found=1; any=1
      fi
    done
    (( found == 1 )) || warn "Selection '$token' did not match a discovered PHP."
  done
  (( any == 1 ))
}

if [[ -z "$PHP_SPEC" && -t 0 && $AUTO_YES -eq 0 ]]; then
  printf '\nPHP version(s) to configure (e.g. 8.2,8.3 or IDs 2,4) [Enter = all]: '
  read -r PHP_SPEC
fi
if ! select_php_by_spec "$PHP_SPEC"; then
  fail "No PHP installation matched --php='$PHP_SPEC'."
  exit 1
fi

if [[ -z "$REQUESTED_VERSION" && -t 0 && $AUTO_YES -eq 0 ]]; then
  printf 'ionCube version to install (e.g. 15.5.0) [Enter = latest]: '
  read -r REQUESTED_VERSION
fi
REQUESTED_VERSION="${REQUESTED_VERSION:-latest}"
if [[ "$REQUESTED_VERSION" != "latest" && ! "$REQUESTED_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  fail "Invalid ionCube version '$REQUESTED_VERSION'. Use e.g. 15.5.0 or latest."
  exit 2
fi

# ---------- download/source helpers ----------
bundle_stem_for_platform() {
  case "$1" in
    x86_64-glibc) echo "ioncube_loaders_lin_x86-64" ;;
    x86_64-musl) echo "ioncube_loaders_lin-musl_x86-64" ;;
    x86-glibc) echo "ioncube_loaders_lin_x86" ;;
    aarch64-glibc) echo "ioncube_loaders_lin_aarch64" ;;
    armv7l-glibc) echo "ioncube_loaders_lin_armv7l" ;;
    *) return 1 ;;
  esac
}

http_get_to_file() {
  local url="$1" out="$2"
  rm -f "$out.part"
  if command_exists curl; then
    curl --fail --location --silent --show-error --retry 2 --connect-timeout 15 --max-time 180 \
      -A "ioncube-universal-installer/${SCRIPT_VERSION}" -o "$out.part" "$url" || { rm -f "$out.part"; return 1; }
  elif command_exists wget; then
    wget -q --tries=2 --timeout=30 -U "ioncube-universal-installer/${SCRIPT_VERSION}" -O "$out.part" "$url" || { rm -f "$out.part"; return 1; }
  else
    fail "Neither curl nor wget is installed."
    return 1
  fi
  tar -tzf "$out.part" >/dev/null 2>&1 || { rm -f "$out.part"; return 1; }
  mv -f "$out.part" "$out"
}

fetch_text() {
  local url="$1"
  if command_exists curl; then
    curl --fail --location --silent --show-error --connect-timeout 12 --max-time 40 \
      -A "ioncube-universal-installer/${SCRIPT_VERSION}" "$url"
  elif command_exists wget; then
    wget -qO- --timeout=30 -U "ioncube-universal-installer/${SCRIPT_VERSION}" "$url"
  else
    return 1
  fi
}

latest_official_version() {
  local txt
  txt="$(fetch_text "$OFFICIAL_RELEASE_FEED" 2>/dev/null || true)"
  printf '%s\n' "$txt" | grep -oE '"[0-9]+\.[0-9]+(\.[0-9]+)?"' | tr -d '"' | sort -V | tail -n1
}

is_trusted_ioncube_url() {
  [[ "$1" =~ ^https://downloads([0-9]+)?\.ioncube\.com/ ]] || [[ "$1" =~ ^https://www\.ioncube\.com/ ]]
}

slackbuilds_lookup() {
  local stem="$1" ver="$2" page html url
  for page in "${SLACKBUILDS_PAGES[@]}"; do
    html="$(fetch_text "$page" 2>/dev/null || true)"
    [[ -n "$html" ]] || continue
    printf '%s\n' "$html" | grep -Fq "ioncube-loader (${ver})" || continue
    url="$(printf '%s\n' "$html" | grep -oE 'https://downloads[0-9]*\.ioncube\.com/loader_downloads/[^"< ]+\.tar\.gz' | grep -F "${stem}_${ver}.tar.gz" | head -n1 || true)"
    [[ -n "$url" ]] && { printf '%s' "$url"; return 0; }
  done
  return 1
}

declare -A BUNDLE_DIR BUNDLE_SOURCE BUNDLE_ARCHIVE
WORK_DIR="$(mktemp -d "${DOWNLOAD_DIR}/run.XXXXXX")"

fetch_bundle_for_platform() {
  local platform="$1" stem latest out exdir url source candidates=() sburl=""
  stem="$(bundle_stem_for_platform "$platform")" || { warn "Unsupported loader platform: $platform"; return 1; }
  out="${WORK_DIR}/${stem}.tar.gz"
  exdir="${WORK_DIR}/${stem}-extract"
  mkdir -p "$exdir"

  if [[ -n "$CUSTOM_SOURCE_URL" ]]; then
    url="$CUSTOM_SOURCE_URL"
    if ! is_trusted_ioncube_url "$url" && (( ALLOW_THIRD_PARTY == 0 )); then
      if [[ -t 0 && $AUTO_YES -eq 0 ]]; then
        warn "The supplied source is not on ioncube.com: $url"
        read -r -p "Use this third-party source? [y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]] || return 1
      else
        fail "Third-party --source-url requires --allow-third-party in non-interactive mode."
        return 1
      fi
    fi
    candidates+=("$url")
  elif [[ "$REQUESTED_VERSION" == "latest" ]]; then
    candidates+=("https://downloads.ioncube.com/loader_downloads/${stem}.tar.gz")
  else
    latest="$(latest_official_version || true)"
    if [[ "$latest" == "$REQUESTED_VERSION" ]]; then
      candidates+=("https://downloads.ioncube.com/loader_downloads/${stem}.tar.gz")
    fi
    # Known historical ionCube CDN naming used by distribution repositories.
    candidates+=("https://downloads3.ioncube.com/loader_downloads/${stem}_${REQUESTED_VERSION}.tar.gz")
    candidates+=("https://downloads.ioncube.com/loader_downloads/${stem}_${REQUESTED_VERSION}.tar.gz")
    sburl="$(slackbuilds_lookup "$stem" "$REQUESTED_VERSION" || true)"
    [[ -n "$sburl" ]] && candidates+=("$sburl")
  fi

  source=""
  for url in "${candidates[@]}"; do
    [[ -n "$url" ]] || continue
    info "Trying source for $platform: $url"
    if http_get_to_file "$url" "$out"; then
      source="$url"
      break
    fi
    warn "Source unavailable/invalid: $url"
  done

  if [[ -z "$source" ]]; then
    fail "Could not obtain ionCube ${REQUESTED_VERSION} bundle for platform $platform."
    if [[ "$REQUESTED_VERSION" != "latest" ]]; then
      fail "Historical releases are not all publicly indexed. You can retry with --source-url=URL."
    fi
    return 1
  fi

  tar -xzf "$out" -C "$exdir"
  BUNDLE_DIR[$platform]="$exdir"
  BUNDLE_SOURCE[$platform]="$source"
  BUNDLE_ARCHIVE[$platform]="$out"
  ok "Bundle ready for $platform."
}

# Unique selected platforms.
declare -A NEED_PLATFORM=()
selected_count=0
for ((i=0; i<${#PHP_BIN[@]}; i++)); do
  (( PHP_SELECTED[$i] == 1 )) || continue
  ((selected_count+=1))
  NEED_PLATFORM["${PHP_PLATFORM[$i]}"]=1
done

section "Loader source"
printf 'Requested ionCube: %s\n' "$REQUESTED_VERSION"
if [[ -n "$CUSTOM_SOURCE_URL" && ${#NEED_PLATFORM[@]} -gt 1 ]]; then
  fail "--source-url points to one platform-specific archive, but selected PHPs require multiple platforms. Select one platform at a time."
  exit 2
fi
if [[ "$REQUESTED_VERSION" == "latest" ]]; then
  latest_hint="$(latest_official_version || true)"
  [[ -n "$latest_hint" ]] && printf 'Current production: %s\n' "$latest_hint"
fi

for platform in "${!NEED_PLATFORM[@]}"; do
  if [[ "$platform" == "unsupported" ]]; then
    warn "At least one selected PHP has an unsupported/unknown CPU platform. It will be skipped."
    continue
  fi
  fetch_bundle_for_platform "$platform" || true
done

# ---------- config target discovery ----------
declare -a CONFIG_TARGETS=() CONFIG_ERROR=() CANDIDATE_FILE=() CANDIDATE_VERSION=() ACTION=() REASON=()

targets_for_instance() {
  local idx="$1" line ini dir label f rf active_count target
  local -A target_seen=() active_seen=()
  local targets="" errors=""

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS='|' read -r ini dir label <<< "$line"
    [[ "$ini" == "(none)" ]] && ini=""
    [[ "$dir" == "(none)" ]] && dir=""

    active_seen=()
    active_count=0
    if [[ -n "$ini" && -f "$ini" ]] && grep -qE '^[[:space:]]*zend_extension[[:space:]]*=.*ioncube' "$ini" 2>/dev/null; then
      rf="$(real_path "$ini")"
      active_seen[$rf]=1
    fi
    if [[ -n "$dir" && -d "$dir" ]]; then
      shopt -s nullglob
      for f in "$dir"/*.ini; do
        grep -qE '^[[:space:]]*zend_extension[[:space:]]*=.*ioncube' "$f" 2>/dev/null || continue
        rf="$(real_path "$f")"
        active_seen[$rf]=1
      done
      shopt -u nullglob
    fi

    active_count="${#active_seen[@]}"
    if (( active_count > 1 )); then
      errors+="${label}: multiple active ionCube ini files; "
      continue
    elif (( active_count == 1 )); then
      for target in "${!active_seen[@]}"; do :; done
    else
      if [[ "${PHP_FAMILY[$idx]}" == "CloudLinux ALT-PHP" && "$dir" == */php.d.all && -d "$dir" ]]; then
        local -a alt_matches=()
        shopt -s nullglob
        for f in "$dir"/*ioncube*.ini "$dir"/*IonCube*.ini; do
          [[ -f "$f" || -L "$f" ]] && alt_matches+=("$(real_path "$f")")
        done
        shopt -u nullglob
        if (( ${#alt_matches[@]} == 1 )); then
          target="${alt_matches[0]}"
        elif (( ${#alt_matches[@]} > 1 )); then
          errors+="${label}: multiple ionCube registry files; "
          continue
        elif [[ -n "$ini" && -f "$ini" ]]; then
          target="$(real_path "$ini")"
        else
          continue
        fi
      elif [[ -n "$dir" && -d "$dir" ]]; then
        target="${dir}/00-ioncube-manual.ini"
      elif [[ -n "$ini" && -f "$ini" ]]; then
        target="$(real_path "$ini")"
      else
        continue
      fi
    fi

    rf="$(real_path "$target")"
    [[ -n "$rf" ]] || rf="$target"
    if [[ -z "${target_seen[$rf]:-}" ]]; then
      target_seen[$rf]=1
      targets+="${rf}"$'\n'
    fi
  done <<< "${PHP_CONTEXTS[$idx]}"

  # CloudLinux ALT-PHP uses php.d.all as module registry. Refuse to invent a new
  # unregistered selector module if ionCube does not already exist there.
  if [[ "${PHP_FAMILY[$idx]}" == "CloudLinux ALT-PHP" ]]; then
    local altroot altall found=0
    altroot="${PHP_BIN[$idx]%/usr/bin/php}"
    altall="${altroot}/etc/php.d.all"
    if [[ -d "$altall" ]]; then
      shopt -s nullglob
      for f in "$altall"/*.ini; do
        if grep -qiE 'ioncube' "$f" 2>/dev/null; then found=1; break; fi
      done
      shopt -u nullglob
    fi
    if (( found == 0 )); then
      errors+="ALT-PHP has no registered ionCube module in php.d.all; install/register the module first or use the CloudLinux package; "
      targets=""
    fi
  fi

  CONFIG_TARGETS[$idx]="$targets"
  CONFIG_ERROR[$idx]="$errors"
}

is_managed_target_version() {
  local idx="$1" ver="$2" file
  while IFS= read -r file; do
    [[ -n "$file" && -f "$file" ]] || continue
    grep -qF "${BASE_DIR}/loaders/${ver}/" "$file" && return 0
  done <<< "${CONFIG_TARGETS[$idx]}"
  return 1
}

section "Compatibility preflight"
printf '%-4s %-8s %-10s %-10s %-12s %s\n' "ID" "PHP" "Current" "Candidate" "Action" "Reason"
printf '%-4s %-8s %-10s %-10s %-12s %s\n' "--" "--------" "----------" "----------" "------------" "------"

change_count=0
compatible_count=0
for ((i=0; i<${#PHP_BIN[@]}; i++)); do
  (( PHP_SELECTED[$i] == 1 )) || continue
  targets_for_instance "$i"
  platform="${PHP_PLATFORM[$i]}"
  dot="${PHP_DOT[$i]}"
  suffix=""
  [[ "${PHP_ZTS[$i]}" == "ts" ]] && suffix="_ts"
  loader_name="ioncube_loader_lin_${dot}${suffix}.so"

  if [[ "$platform" == "unsupported" || -z "${BUNDLE_DIR[$platform]:-}" ]]; then
    ACTION[$i]="SKIP"; REASON[$i]="no loader bundle for ${platform}"; CANDIDATE_VERSION[$i]="-"
  else
    loader="${BUNDLE_DIR[$platform]}/ioncube/${loader_name}"
    CANDIDATE_FILE[$i]="$loader"
    if [[ ! -f "$loader" ]]; then
      ACTION[$i]="SKIP"; REASON[$i]="bundle has no ${loader_name}"; CANDIDATE_VERSION[$i]="-"
    elif [[ -n "${CONFIG_ERROR[$i]}" ]]; then
      ACTION[$i]="SKIP"; REASON[$i]="${CONFIG_ERROR[$i]}"; CANDIDATE_VERSION[$i]="-"
    elif [[ -z "${CONFIG_TARGETS[$i]}" ]]; then
      ACTION[$i]="SKIP"; REASON[$i]="no safe PHP configuration target found"; CANDIDATE_VERSION[$i]="-"
    else
      test_out="$(${PHP_BIN[$i]} -n -d "zend_extension=${loader}" -v 2>&1 || true)"
      cand="$(printf '%s\n' "$test_out" | extract_ioncube_version)"
      if [[ -z "$cand" ]]; then
        ACTION[$i]="SKIP"; REASON[$i]="loader compatibility test failed"; CANDIDATE_VERSION[$i]="-"
      elif [[ "$REQUESTED_VERSION" != "latest" && "$cand" != "$REQUESTED_VERSION" ]]; then
        ACTION[$i]="SKIP"; REASON[$i]="downloaded loader is ${cand}, not requested ${REQUESTED_VERSION}"; CANDIDATE_VERSION[$i]="$cand"
      else
        CANDIDATE_VERSION[$i]="$cand"
        ((compatible_count+=1))
        cur="${PHP_CURRENT[$i]}"
        if [[ "$cur" == "$cand" ]]; then
          if is_managed_target_version "$i" "$cand"; then
            ACTION[$i]="CURRENT"; REASON[$i]="already manually managed at requested version"
          else
            ACTION[$i]="REPOINT"; REASON[$i]="same version loaded; switch config to manual managed loader"
            ((change_count+=1))
          fi
        elif [[ "$cur" == "none" || "$cur" == "-" ]]; then
          ACTION[$i]="INSTALL"; REASON[$i]="ionCube not currently loaded"; ((change_count+=1))
        else
          cmp="$(version_cmp "$cand" "$cur")"
          if [[ "$cmp" == "1" ]]; then
            ACTION[$i]="UPGRADE"; REASON[$i]="newer requested loader"; ((change_count+=1))
          else
            ACTION[$i]="DOWNGRADE"; REASON[$i]="explicit older version requested"; ((change_count+=1))
          fi
        fi
      fi
    fi
  fi

  printf '%-4s %-8s %-10s %-10s %-12s %s\n' \
    "$((i+1))" "${PHP_DOT[$i]}" "${PHP_CURRENT[$i]}" "${CANDIDATE_VERSION[$i]:--}" "${ACTION[$i]}" "${REASON[$i]}"
done

if (( compatible_count == 0 )); then
  fail "No selected PHP installation has a compatible, verifiable loader/configuration path."
  exit 1
fi

if (( DRY_RUN == 1 )); then
  ok "Dry-run complete. No server files were modified."
  exit 0
fi

if (( change_count == 0 )); then
  info "Selected PHP installations are already manually managed at the requested version."
  # Still allow CageFS refresh/recycle if our managed path exists.
fi

if (( AUTO_YES == 0 )); then
  printf '\n%s%d installation(s) will have configuration changed.%s\n' "$C_BOLD" "$change_count" "$C_RESET"
  read -r -p "Continue? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { warn "Cancelled."; exit 0; }
fi

# ---------- backup helpers ----------
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}"
mkdir -p "$BACKUP_DIR/files"
MANIFEST="${BACKUP_DIR}/manifest.tsv"
: > "$MANIFEST"
printf 'script_version=%s\ncreated=%s\nrequested=%s\n' "$SCRIPT_VERSION" "$(date -Is)" "$REQUESTED_VERSION" > "${BACKUP_DIR}/metadata.txt"

declare -A BACKED_UP=()
backup_file() {
  local f="$1" dest
  [[ -n "${BACKED_UP[$f]:-}" ]] && return 0
  BACKED_UP[$f]=1
  if [[ -e "$f" || -L "$f" ]]; then
    printf 'EXIST\t%s\n' "$f" >> "$MANIFEST"
    dest="${BACKUP_DIR}/files${f}"
    mkdir -p "$(dirname "$dest")"
    cp -a "$f" "$dest"
  else
    printf 'MISSING\t%s\n' "$f" >> "$MANIFEST"
  fi
}

restore_file_from_backup() {
  local f="$1" dest="${BACKUP_DIR}/files${1}"
  if grep -Fqx $'EXIST\t'"$f" "$MANIFEST"; then
    mkdir -p "$(dirname "$f")"
    rm -f "$f"
    cp -a "$dest" "$f"
  elif grep -Fqx $'MISSING\t'"$f" "$MANIFEST"; then
    rm -f "$f"
  fi
}

write_loader_directive() {
  local f="$1" loader="$2" tmp active
  mkdir -p "$(dirname "$f")"
  backup_file "$f"
  tmp="${f}.ioncube-universal.$$"

  if [[ -f "$f" ]]; then
    active="$(grep -cE '^[[:space:]]*zend_extension[[:space:]]*=.*ioncube' "$f" 2>/dev/null || true)"
    if (( active > 1 )); then
      fail "Refusing to edit $f: more than one active ionCube zend_extension line."
      return 1
    fi
    if (( active == 1 )); then
      awk -v loader="$loader" '
        BEGIN {done=0}
        /^[[:space:]]*zend_extension[[:space:]]*=.*[iI][oO][nN][cC][uU][bB][eE]/ && done==0 {
          print "; Managed by ioncube-universal-installer.sh"
          print "zend_extension=\"" loader "\""
          done=1
          next
        }
        {print}
      ' "$f" > "$tmp"
    else
      cat "$f" > "$tmp"
      printf '\n; Managed by ioncube-universal-installer.sh\nzend_extension="%s"\n' "$loader" >> "$tmp"
    fi
  else
    cat > "$tmp" <<INI
; Managed by ioncube-universal-installer.sh
zend_extension="${loader}"
INI
  fi

  chmod --reference="$f" "$tmp" 2>/dev/null || chmod 0644 "$tmp"
  chown --reference="$f" "$tmp" 2>/dev/null || chown root:root "$tmp"
  mv -f "$tmp" "$f"
}

ok "Backup directory: $BACKUP_DIR"

# ---------- copy loaders and apply PHP config ----------
declare -a CHANGED_IDX=()
section "Install and configure loaders"
for ((i=0; i<${#PHP_BIN[@]}; i++)); do
  (( PHP_SELECTED[$i] == 1 )) || continue
  case "${ACTION[$i]:-SKIP}" in
    INSTALL|UPGRADE|DOWNGRADE|REPOINT) ;;
    *) continue ;;
  esac

  cand="${CANDIDATE_VERSION[$i]}"
  platform="${PHP_PLATFORM[$i]}"
  src="${CANDIDATE_FILE[$i]}"
  fname="$(basename "$src")"
  destdir="${LOADERS_DIR}/${cand}/${platform}"
  dest="${destdir}/${fname}"
  mkdir -p "$destdir"
  if [[ ! -f "$dest" ]] || ! cmp -s "$src" "$dest"; then
    cp -f "$src" "$dest"
    chown root:root "$dest"
    chmod 0755 "$dest"
  fi

  info "PHP ${PHP_DOT[$i]} (${PHP_FAMILY[$i]}): ${ACTION[$i]} -> ionCube ${cand}"
  changed_files=()
  config_failed=0
  while IFS= read -r cfg; do
    [[ -n "$cfg" ]] || continue
    if write_loader_directive "$cfg" "$dest"; then
      changed_files+=("$cfg")
      info "Configured: $cfg"
    else
      config_failed=1
      break
    fi
  done <<< "${CONFIG_TARGETS[$i]}"

  if (( config_failed == 1 )); then
    fail "Configuration failed for PHP ${PHP_DOT[$i]}; restoring its changed files."
    for cfg in "${changed_files[@]}"; do restore_file_from_backup "$cfg"; done
    ACTION[$i]="FAILED"
    continue
  fi
  CHANGED_IDX+=("$i")
done

# ---------- CloudLinux ALT-PHP propagation ----------
alt_changed=0
for i in "${CHANGED_IDX[@]:-}"; do
  [[ -n "$i" ]] || continue
  [[ "${PHP_FAMILY[$i]}" == "CloudLinux ALT-PHP" ]] && alt_changed=1
done
if (( alt_changed == 1 )) && command_exists cagefsctl; then
  section "CloudLinux ALT-PHP propagation"
  info "Running cagefsctl --rebuild-alt-php-ini ..."
  if out="$(cagefsctl --rebuild-alt-php-ini 2>&1)"; then
    [[ -n "$out" ]] && printf '%s\n' "$out"
    ok "ALT-PHP user ini files rebuilt."
  else
    rc=$?; [[ -n "$out" ]] && printf '%s\n' "$out"
    warn "cagefsctl --rebuild-alt-php-ini returned exit code $rc. ALT-PHP users should be checked manually."
  fi
fi

# ---------- CageFS integration ----------
if command_exists cagefsctl && [[ -d /etc/cagefs/conf.d ]]; then
  section "CloudLinux CageFS"
  backup_file "$CAGE_CFG"
  cat > "${CAGE_CFG}.tmp.$$" <<CAGE
[ioncube-universal]
comment=Manual ionCube Loaders managed by ioncube-universal-installer.sh
paths=${BASE_DIR}
CAGE
  chmod 0644 "${CAGE_CFG}.tmp.$$"
  chown root:root "${CAGE_CFG}.tmp.$$"
  mv -f "${CAGE_CFG}.tmp.$$" "$CAGE_CFG"
  info "Running cagefsctl --force-update ..."
  if cage_out="$(cagefsctl --force-update 2>&1)"; then
    [[ -n "$cage_out" ]] && printf '%s\n' "$cage_out"
    if printf '%s\n' "$cage_out" | grep -qiE 'PermissionError|Permission denied'; then
      warn "CageFS completed with a permission warning. Managed loader visibility will still be checked."
    else
      ok "CageFS force-update completed."
    fi
  else
    rc=$?; [[ -n "$cage_out" ]] && printf '%s\n' "$cage_out"
    warn "cagefsctl --force-update returned exit code $rc. Host-side configuration remains installed."
  fi
  if [[ -e "/usr/share/cagefs-skeleton${BASE_DIR}" ]]; then
    ok "Managed ionCube directory is visible in CageFS skeleton."
  else
    warn "Could not confirm ${BASE_DIR} inside /usr/share/cagefs-skeleton."
  fi
fi

# ---------- handler/web process recycle ----------
reload_service() {
  local svc="$1"
  if command_exists systemctl; then
    systemctl is-active --quiet "$svc" 2>/dev/null || return 1
    if systemctl reload "$svc" >/dev/null 2>&1; then
      ok "Reloaded service: $svc"
    elif systemctl restart "$svc" >/dev/null 2>&1; then
      ok "Restarted service: $svc"
    else
      warn "Could not reload/restart service: $svc"
      return 1
    fi
  elif command_exists service; then
    service "$svc" reload >/dev/null 2>&1 || service "$svc" restart >/dev/null 2>&1 || return 1
    ok "Reloaded/restarted service: $svc"
  else
    return 1
  fi
}

selected_version_matches_unit() {
  local unit="$1" i dot key
  for i in "${CHANGED_IDX[@]:-}"; do
    [[ -n "$i" ]] || continue
    dot="${PHP_DOT[$i]}"; key="${dot//./}"
    [[ "$unit" == *"$dot"* || "$unit" == *"$key"* ]] && return 0
  done
  return 1
}

if (( NO_RESTART == 0 )); then
  section "Recycle/reload PHP handlers"

  if [[ -d /usr/local/lsws/admin/tmp ]]; then
    touch /usr/local/lsws/admin/tmp/.lsphp_restart.txt
    ok "Requested graceful LiteSpeed/OpenLiteSpeed LSPHP recycle."
  fi

  # Reload active PHP-FPM services that clearly match selected PHP versions.
  # Avoid process substitution here for maximum compatibility with older hosting OS shells.
  if command_exists systemctl; then
    fpm_units_file="${WORK_DIR}/running-fpm-units.txt"
    : > "$fpm_units_file"

    systemctl list-units --type=service --state=running --no-legend 2>/dev/null \
      | awk '{print $1}' \
      | grep -Ei '(^|[-_.])(php.*fpm|fpm.*php|ea-php.*php-fpm|plesk-php.*fpm)' \
      > "$fpm_units_file" || true

    while IFS= read -r unit; do
      [[ -n "$unit" ]] || continue
      selected_version_matches_unit "$unit" || continue
      reload_service "$unit" || true
    done < "$fpm_units_file"
  fi

  # Generic RHEL-family php-fpm.service may not encode the PHP version in its unit name.
  generic_system_fpm=0
  for i in "${CHANGED_IDX[@]:-}"; do
    [[ -n "$i" ]] || continue
    [[ "${PHP_FAMILY[$i]}" == "System PHP" ]] && generic_system_fpm=1
  done
  (( generic_system_fpm == 1 )) && reload_service php-fpm >/dev/null 2>&1 || true

  # Common generic FPM service names (SysV/systemd fallback).
  for i in "${CHANGED_IDX[@]:-}"; do
    [[ -n "$i" ]] || continue
    dot="${PHP_DOT[$i]}"; key="${dot//./}"
    for svc in "php${dot}-fpm" "php${key}-fpm" "php-fpm${key}" "ea-php${key}-php-fpm" "plesk-php${key}-fpm"; do
      reload_service "$svc" >/dev/null 2>&1 || true
    done
  done

  # Apache graceful reload covers mod_php, mod_lsapi, suPHP/CGI config changes.
  if [[ -x /usr/local/cpanel/scripts/restartsrv_httpd ]]; then
    /usr/local/cpanel/scripts/restartsrv_httpd --graceful >/dev/null 2>&1 && ok "Gracefully restarted cPanel Apache." || true
  elif command_exists apachectl; then
    apachectl graceful >/dev/null 2>&1 && ok "Apache graceful reload requested." || true
  elif command_exists apache2ctl; then
    apache2ctl graceful >/dev/null 2>&1 && ok "Apache graceful reload requested." || true
  elif pgrep -x httpd >/dev/null 2>&1; then
    reload_service httpd || true
  elif pgrep -x apache2 >/dev/null 2>&1; then
    reload_service apache2 || true
  fi

  info "Nginx itself does not execute PHP; no Nginx restart is required for ionCube."
else
  warn "Handler recycle/reload skipped by --no-restart."
fi

# ---------- verification ----------
section "Verification"
verify_failures=0
for i in "${CHANGED_IDX[@]:-}"; do
  [[ -n "$i" ]] || continue
  expected="${CANDIDATE_VERSION[$i]}"
  got="$(current_loader_version "${PHP_BIN[$i]}")"
  if [[ "$got" == "$expected" ]]; then
    ok "PHP ${PHP_DOT[$i]} ${PHP_FAMILY[$i]} CLI: ionCube ${got}"
  else
    warn "PHP ${PHP_DOT[$i]} ${PHP_FAMILY[$i]} CLI: expected ${expected}, got ${got}"
    ((verify_failures+=1))
  fi

  bindir="$(dirname "${PHP_BIN[$i]}")"
  for hb in "$bindir/php-cgi" "$bindir/php-fpm" "$bindir/lsphp"; do
    [[ -x "$hb" ]] || continue
    hgot="$(current_loader_version "$hb")"
    if [[ "$hgot" == "$expected" ]]; then
      ok "  $(basename "$hb"): ionCube ${hgot}"
    else
      warn "  $(basename "$hb"): expected ${expected}, got ${hgot}"
    fi
  done
done

if [[ -n "$VERIFY_USER" && $(command -v cagefs_enter_user 2>/dev/null || true) ]]; then
  section "Verify inside CageFS user: $VERIFY_USER"
  if id "$VERIFY_USER" >/dev/null 2>&1; then
    for i in "${CHANGED_IDX[@]:-}"; do
      [[ -n "$i" ]] || continue
      expected="${CANDIDATE_VERSION[$i]}"
      if out="$(cagefs_enter_user "$VERIFY_USER" "${PHP_BIN[$i]}" -v 2>&1)"; then
        got="$(printf '%s\n' "$out" | extract_ioncube_version)"
        [[ "$got" == "$expected" ]] && ok "CageFS ${VERIFY_USER}, PHP ${PHP_DOT[$i]}: ionCube ${got}" || warn "CageFS ${VERIFY_USER}, PHP ${PHP_DOT[$i]}: expected ${expected}, got ${got:-unknown}"
      else
        warn "CageFS verification failed for ${VERIFY_USER} / ${PHP_BIN[$i]}"
      fi
    done
  else
    warn "CageFS verification user '$VERIFY_USER' does not exist."
  fi
fi

# ---------- rollback helper ----------
cat > "${BACKUP_DIR}/rollback.sh" <<'ROLLBACK'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/manifest.tsv"
while IFS=$'\t' read -r state path; do
  [[ -n "$path" ]] || continue
  if [[ "$state" == "EXIST" ]]; then
    mkdir -p "$(dirname "$path")"
    rm -f "$path"
    cp -a "$HERE/files$path" "$path"
  elif [[ "$state" == "MISSING" ]]; then
    rm -f "$path"
  fi
done < "$MANIFEST"
if command -v cagefsctl >/dev/null 2>&1; then cagefsctl --force-update || true; fi
if [[ -d /usr/local/lsws/admin/tmp ]]; then touch /usr/local/lsws/admin/tmp/.lsphp_restart.txt; fi
echo "Rollback files restored. Reload/restart the relevant PHP-FPM/Apache service if needed."
ROLLBACK
chmod 0700 "${BACKUP_DIR}/rollback.sh"

# Refresh status values.
for ((i=0; i<${#PHP_BIN[@]}; i++)); do PHP_CURRENT[$i]="$(current_loader_version "${PHP_BIN[$i]}")"; done
show_php_status "Final host-side status"

section "Done"
printf 'Backup   : %s\n' "$BACKUP_DIR"
printf 'Rollback : %s\n' "${BACKUP_DIR}/rollback.sh"
printf 'Log      : %s\n' "$LOG_FILE"

if (( verify_failures > 0 )); then
  warn "$verify_failures CLI verification(s) did not show the expected loader. Check the log and per-SAPI/per-domain PHP configuration."
  exit 3
fi
ok "ionCube manual installation workflow completed."
printf '\nNote: per-domain php.ini/PHPRC overrides can still differ from host CLI. For a critical site, verify with phpinfo() after its worker has recycled.\n'
