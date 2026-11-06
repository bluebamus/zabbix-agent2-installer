#!/usr/bin/env bash
# 갱신한 설정을 적용하고 에이전트를 기동·검증한다
# 사용법: sudo ./03_deploy/deploy_agent2.sh <에이전트 IP> [conf 경로(기본 02_configure/zabbix_agent2.conf)]
#   인자가 없으면 에이전트 IP 를 물어본다.
set -euo pipefail

AGENT_IP=${1:-}
CONF=${2:-$(dirname "$0")/../02_configure/zabbix_agent2.conf}
[[ -n $AGENT_IP ]] || read -rp "에이전트 IP: " AGENT_IP
[[ $AGENT_IP =~ ^[A-Za-z0-9.:_-]+$ ]] || { echo "에이전트 IP 형식 오류: '$AGENT_IP'" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "root 권한이 필요합니다: sudo $0 $*" >&2; exit 1; }
[[ -r $CONF ]] || { echo "설정 파일이 없습니다: $CONF" >&2; exit 1; }
DEST=/etc/zabbix/zabbix_agent2.conf

echo "[1/5] 설정 문법 검사"
zabbix_agent2 -T -c "$CONF" >/dev/null

echo "[2/5] 설정 복사 → $DEST (기존 파일은 .bak.<시각> 으로 보관)"
[[ -f $DEST ]] && cp -a "$DEST" "$DEST.bak.$(date +%Y%m%d%H%M%S)"
cp "$CONF" "$DEST"

echo "[3/5] 서비스 등록·기동"
systemctl enable --now zabbix-agent2
systemctl restart zabbix-agent2   # 이미 실행 중이면 enable --now 만으로는 새 설정이 반영되지 않는다

echo "[4/5] 버전"
zabbix_agent2 -V | head -1

echo "[5/5] zabbix_get -s $AGENT_IP -k agent.ping"
for _ in $(seq 10); do
  out=$(zabbix_get -s "$AGENT_IP" -k agent.ping 2>&1) && [[ $out == 1 ]] && break
  sleep 1
done
echo "$out"
if [[ $out != 1 ]]; then
  echo "agent.ping 실패. 확인: 설정 파일의 Server= 에 이 명령을 실행한 호스트 IP 포함 여부, 방화벽 10050/tcp, journalctl -u zabbix-agent2" >&2
  exit 1
fi
echo "정상: 에이전트가 응답합니다."
