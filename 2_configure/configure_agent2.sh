#!/usr/bin/env bash
# zabbix_agent2.conf 의 Server / ServerActive / Hostname / HostMetadata(선택) 값을 갱신한다 (기본 대상: 이 스크립트 옆의 zabbix_agent2.conf)
# 사용법:
#   ./2_configure/configure_agent2.sh Server=10.0.0.10 ServerActive=10.0.0.10:10051 Hostname=mysql-prod-01 HostMetadata=linux,mysql,prod
#   ./2_configure/configure_agent2.sh -f agent.env            # 파일에 위 항목을 한 줄에 하나씩 KEY=VALUE 형식으로 작성
#   ./2_configure/configure_agent2.sh                         # 대화형 입력
#   HostMetadata 는 선택(자동 등록용). 생략하면 기존 값(기본: 주석 처리)을 그대로 둔다.
#   마지막 인자로 다른 conf 경로를 줄 수 있다:  ... Hostname=web-01 /path/zabbix_agent2.conf
set -euo pipefail

CONF="$(dirname "$0")/zabbix_agent2.conf"   # 기본: 2_configure/zabbix_agent2.conf
declare -A V=()

set_kv() {
  case $1 in
    Server=*|ServerActive=*|Hostname=*|HostMetadata=*) V[${1%%=*}]=${1#*=} ;;
    *) echo "알 수 없는 항목: '$1' (Server=, ServerActive=, Hostname=, HostMetadata= 만 허용)" >&2; exit 1 ;;
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

# 아무 값도 주지 않았을 때만 HostMetadata 까지 묻는다 (일부만 준 자동화 실행이 입력 대기로 멈추지 않게)
INTERACTIVE=$(( ${#V[@]} == 0 ))
[[ -n ${V[Server]:-} ]]       || read -rp "Server (Zabbix 서버 IP): " 'V[Server]'
[[ -n ${V[ServerActive]:-} ]] || read -rp "ServerActive (Zabbix 서버 IP) [${V[Server]}]: " 'V[ServerActive]'
V[ServerActive]=${V[ServerActive]:-${V[Server]}}
[[ -n ${V[Hostname]:-} ]]     || read -rp "Hostname (웹 UI에 등록할 호스트명): " 'V[Hostname]'
if ((INTERACTIVE)); then
  read -rp "HostMetadata (자동 등록용, 예: linux,mysql,prod / 비우면 생략): " 'V[HostMetadata]' || true
fi
[[ -n ${V[HostMetadata]:-} ]] || unset 'V[HostMetadata]'

# 입력 검증: sed 구분자(|)·역슬래시·& 등이 들어갈 수 없도록 허용 문자만 통과
[[ ${V[Server]} =~ ^[A-Za-z0-9.:,/_-]+$ ]]           || { echo "Server 값이 올바르지 않습니다: '${V[Server]}'" >&2; exit 1; }
[[ ${V[ServerActive]} =~ ^[][A-Za-z0-9.:,\;_-]+$ ]]  || { echo "ServerActive 값이 올바르지 않습니다: '${V[ServerActive]}'" >&2; exit 1; }
[[ ${V[Hostname]} =~ ^[A-Za-z0-9._\ -]{1,128}$ ]]    || { echo "Hostname 은 영문·숫자·공백·. _ - 만, 128자 이하: '${V[Hostname]}'" >&2; exit 1; }
if [[ -v V[HostMetadata] ]]; then
  # 길이는 따로 검사: bash 정규식 반복 상한(255) 때문에 {1,2034} 를 쓸 수 없다
  [[ ${V[HostMetadata]} =~ ^[A-Za-z0-9.,:\;_=@/\ -]+$ && ${#V[HostMetadata]} -le 2034 ]] \
    || { echo "HostMetadata 는 영문·숫자·공백·. , : ; _ = @ / - 만, 2034자 이하: '${V[HostMetadata]}'" >&2; exit 1; }
fi
[[ -w $CONF ]] || { echo "설정 파일이 없거나 쓸 수 없습니다: $CONF" >&2; exit 1; }

sed -i -E \
  -e "s|^Server=.*|Server=${V[Server]}|" \
  -e "s|^ServerActive=.*|ServerActive=${V[ServerActive]}|" \
  -e "s|^Hostname=.*|Hostname=${V[Hostname]}|" \
  "$CONF"
# 기본 설정에는 '# HostMetadata=' 로 주석 처리되어 있으므로 주석을 풀면서 값을 넣는다
if [[ -v V[HostMetadata] ]]; then
  sed -i -E "s|^(# )?HostMetadata=.*|HostMetadata=${V[HostMetadata]}|" "$CONF"
fi

# 자체 점검: 입력한 각 키가 정확히 한 줄, 입력값으로 반영되었는지
for k in "${!V[@]}"; do
  [[ $(grep -c "^$k=" "$CONF") -eq 1 ]] && grep -qxF "$k=${V[$k]}" "$CONF" \
    || { echo "반영 실패: $k (설정 파일에 '$k=' 줄이 정확히 1개 있어야 합니다)" >&2; exit 1; }
done

echo "갱신 완료: $CONF"
grep -E '^(Server|ServerActive|Hostname|HostMetadata)=' "$CONF"
