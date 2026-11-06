#!/usr/bin/env bash
# zabbix_agent2.conf 의 Server / ServerActive / Hostname 값을 갱신한다 (기본 대상: ./zabbix_agent2.conf)
# 사용법:
#   ./configure_agent2.sh Server=10.0.0.10 ServerActive=10.0.0.10 Hostname=web-01
#   ./configure_agent2.sh -f agent.env            # 파일에 위 3줄을 KEY=VALUE 형식으로 작성
#   ./configure_agent2.sh                         # 대화형 입력
#   마지막 인자로 다른 conf 경로를 줄 수 있다:  ... Hostname=web-01 /path/zabbix_agent2.conf
set -euo pipefail

CONF="./zabbix_agent2.conf"
declare -A V=()

set_kv() {
  case $1 in
    Server=*|ServerActive=*|Hostname=*) V[${1%%=*}]=${1#*=} ;;
    *) echo "알 수 없는 항목: '$1' (Server=, ServerActive=, Hostname= 만 허용)" >&2; exit 1 ;;
  esac
}

while (($#)); do
  case $1 in
    -f) [[ -r ${2:-} ]] || { echo "입력 파일을 읽을 수 없습니다: ${2:-}" >&2; exit 1; }
        while IFS= read -r line || [[ -n $line ]]; do
          line=${line%$'\r'}
          [[ -z $line || $line == \#* ]] && continue
          set_kv "$line"
        done <"$2"; shift 2 ;;
    *=*) set_kv "$1"; shift ;;
    *) CONF=$1; shift ;;
  esac
done

[[ -n ${V[Server]:-} ]]       || read -rp "Server (Zabbix 서버 IP): " 'V[Server]'
[[ -n ${V[ServerActive]:-} ]] || read -rp "ServerActive (Zabbix 서버 IP) [${V[Server]}]: " 'V[ServerActive]'
V[ServerActive]=${V[ServerActive]:-${V[Server]}}
[[ -n ${V[Hostname]:-} ]]     || read -rp "Hostname (웹 UI에 등록할 호스트명): " 'V[Hostname]'

# 입력 검증: sed 구분자(|)·역슬래시·& 등이 들어갈 수 없도록 허용 문자만 통과
[[ ${V[Server]} =~ ^[A-Za-z0-9.:,/_-]+$ ]]           || { echo "Server 값이 올바르지 않습니다: '${V[Server]}'" >&2; exit 1; }
[[ ${V[ServerActive]} =~ ^[][A-Za-z0-9.:,\;_-]+$ ]]  || { echo "ServerActive 값이 올바르지 않습니다: '${V[ServerActive]}'" >&2; exit 1; }
[[ ${V[Hostname]} =~ ^[A-Za-z0-9._\ -]{1,128}$ ]]    || { echo "Hostname 은 영문·숫자·공백·. _ - 만, 128자 이하: '${V[Hostname]}'" >&2; exit 1; }
[[ -w $CONF ]] || { echo "설정 파일이 없거나 쓸 수 없습니다: $CONF" >&2; exit 1; }

sed -i -E \
  -e "s|^Server=.*|Server=${V[Server]}|" \
  -e "s|^ServerActive=.*|ServerActive=${V[ServerActive]}|" \
  -e "s|^Hostname=.*|Hostname=${V[Hostname]}|" \
  "$CONF"

# 자체 점검: 각 키가 정확히 한 줄, 입력값으로 반영되었는지
for k in Server ServerActive Hostname; do
  [[ $(grep -c "^$k=" "$CONF") -eq 1 ]] && grep -qxF "$k=${V[$k]}" "$CONF" \
    || { echo "반영 실패: $k (설정 파일에 활성 '$k=' 줄이 정확히 1개 있어야 합니다)" >&2; exit 1; }
done

echo "갱신 완료: $CONF"
grep -E '^(Server|ServerActive|Hostname)=' "$CONF"
