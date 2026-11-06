#!/usr/bin/env bash
# Zabbix agent2 설치 (Ubuntu, 공식 repo.zabbix.com 저장소)
# 사용법: sudo ./install_agent2.sh [버전]
#   버전 생략 → 7.4 (7.4 계열 최신)
#   7.4.16    → 7.4 저장소에서 정확히 7.4.16 고정 설치
set -euo pipefail

VERSION="${1:-7.4}"
[[ $VERSION =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "버전 형식 오류: '$VERSION' (예: 7.4, 7.4.16)" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "root 권한이 필요합니다: sudo $0 $*" >&2; exit 1; }

MAJOR=$(cut -d. -f1-2 <<<"$VERSION")
# /etc/os-release 는 VERSION 변수를 덮어쓰므로 서브셸에서 읽는다
OS_ID=$(. /etc/os-release; echo "$ID")
OS_VER=$(. /etc/os-release; echo "$VERSION_ID")
[[ $OS_ID == ubuntu ]] || { echo "Ubuntu 전용 스크립트입니다 (현재: $OS_ID)" >&2; exit 1; }

DEB="zabbix-release_latest_${MAJOR}+ubuntu${OS_VER}_all.deb"
URL="https://repo.zabbix.com/zabbix/${MAJOR}/release/ubuntu/pool/main/z/zabbix-release/${DEB}"
export DEBIAN_FRONTEND=noninteractive

echo "[1/3] Zabbix ${MAJOR} 저장소 등록 (Ubuntu ${OS_VER})"
apt-get update -qq
apt-get install -y -qq wget ca-certificates >/dev/null
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
wget -q -O "$tmp/$DEB" "$URL" || { echo "release 패키지를 받을 수 없습니다: $URL" >&2; exit 1; }
dpkg -i "$tmp/$DEB" >/dev/null
apt-get update -qq

echo "[2/3] 설치할 패키지 버전 결정"
PKGVER=""
if [[ $VERSION != "$MAJOR" ]]; then
  # madison 은 최신순 정렬 → 같은 버전의 가장 높은 리비전(-2 등)을 고른다
  PKGVER=$(apt-cache madison zabbix-agent2 | awk -v v="1:${VERSION}-" 'index($3, v) == 1 { print $3; exit }')
  [[ -n $PKGVER ]] || { echo "저장소에 zabbix-agent2 ${VERSION} 이 없습니다. 가능한 버전:" >&2; apt-cache madison zabbix-agent2 >&2; exit 1; }
fi
echo "  zabbix-agent2 ${PKGVER:-<${MAJOR} 최신>}"

echo "[3/3] zabbix-agent2, zabbix-get 설치"
# zabbix-get 은 점검용 클라이언트라 버전 고정하지 않는다
apt-get install -y -qq --allow-downgrades "zabbix-agent2${PKGVER:+=$PKGVER}" zabbix-get >/dev/null

zabbix_agent2 -V | head -1
echo "설치 완료. 다음: ./configure_agent2.sh Server=<IP> ServerActive=<IP> Hostname=<호스트명>"
