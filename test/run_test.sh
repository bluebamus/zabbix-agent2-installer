#!/usr/bin/env bash
# WSL(또는 Linux)의 Docker 에서 Ubuntu 26.04 컨테이너를 띄워 세 스크립트를 실제로 실행·검증한다.
# 사용법: bash test/run_test.sh      (저장소 루트에서)
# 종료 시 컨테이너와 테스트 이미지를 항상 삭제한다.
set -euo pipefail
cd "$(dirname "$0")/.."

IMG=zbx-agent2-test:26.04
CT=zbx-agent2-test
HOSTNAME_UI=ubuntu2604-test

cleanup() { docker rm -f "$CT" >/dev/null 2>&1 || true; docker rmi "$IMG" >/dev/null 2>&1 || true; echo "[정리] 컨테이너·이미지 삭제 완료"; }
trap cleanup EXIT
ok()   { echo "  PASS: $*"; }
fail() { echo "  FAIL: $*" >&2; exit 1; }
x()    { docker exec -w /opt/installer "$CT" bash -c "$1"; }

echo "== 이미지 빌드 / systemd 컨테이너 기동"
docker build -q -t "$IMG" test >/dev/null
docker run -d --name "$CT" --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /run/lock "$IMG" >/dev/null
for _ in $(seq 30); do x 'systemctl is-system-running 2>/dev/null' | grep -qE 'running|degraded' && break; sleep 1; done
docker exec "$CT" mkdir -p /opt/installer
tar -c install_agent2.sh configure_agent2.sh deploy_agent2.sh zabbix_agent2.conf | docker exec -i "$CT" tar -x -C /opt/installer
x 'chmod +x *.sh'
AGENT_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CT")
x 'grep PRETTY_NAME /etc/os-release'; echo "  에이전트 IP: $AGENT_IP"

echo "== 1. install_agent2.sh"
x './install_agent2.sh 7.x' >/dev/null 2>&1 && fail "잘못된 버전 형식을 거부해야 함"; ok "잘못된 버전 형식 거부"
x './install_agent2.sh 7.4.15'
x 'zabbix_agent2 -V | head -1' | grep -q '7\.4\.15' || fail "7.4.15 고정 설치"; ok "버전 지정(7.4.15) 설치"
x './install_agent2.sh'
x 'zabbix_agent2 -V | head -1' | grep -q '7\.4\.16' || fail "기본값 7.4 → 최신 7.4.16"; ok "버전 생략 → 7.4 최신(7.4.16)"
x 'command -v zabbix_get' >/dev/null || fail "zabbix_get 미설치"; ok "zabbix_get 설치"

echo "== 2. configure_agent2.sh"
x './configure_agent2.sh Server=1.2.3.4 ServerActive=1.2.3.4 "Hostname=bad|name"' >/dev/null 2>&1 && fail "잘못된 Hostname 거부해야 함"; ok "잘못된 Hostname 거부"
x "printf 'Server=$AGENT_IP\r\nServerActive=$AGENT_IP:10051\r\nHostname=$HOSTNAME_UI\r\n' > agent.env && ./configure_agent2.sh -f agent.env"
x "printf '%s\n' 10.9.9.9 '' interactive-host | ./configure_agent2.sh /tmp/x.conf" >/dev/null 2>&1 && fail "없는 conf 거부해야 함"
x "cp zabbix_agent2.conf /tmp/i.conf && printf '%s\n' 10.9.9.9 '' interactive-host | ./configure_agent2.sh /tmp/i.conf >/dev/null && grep -qx ServerActive=10.9.9.9 /tmp/i.conf && grep -qx Hostname=interactive-host /tmp/i.conf" \
  || fail "대화형 입력"; ok "대화형 입력(ServerActive 기본값=Server)"
x "./configure_agent2.sh Server=$AGENT_IP ServerActive=$AGENT_IP Hostname=$HOSTNAME_UI" ; ok "인자 입력 반영"

echo "== 3. deploy_agent2.sh $AGENT_IP"
x "./deploy_agent2.sh $AGENT_IP"
x "grep -qx Server=$AGENT_IP /etc/zabbix/zabbix_agent2.conf && grep -qx Hostname=$HOSTNAME_UI /etc/zabbix/zabbix_agent2.conf" || fail "/etc 설정 반영"; ok "/etc/zabbix/zabbix_agent2.conf 반영"
[[ $(x 'systemctl is-enabled zabbix-agent2') == enabled ]] || fail "enable"; ok "서비스 enabled"
[[ $(x 'systemctl is-active zabbix-agent2') == active ]] || fail "active"; ok "서비스 active"
[[ $(x "zabbix_get -s $AGENT_IP -k agent.hostname") == "$HOSTNAME_UI" ]] || fail "agent.hostname"; ok "agent.hostname = $HOSTNAME_UI"
x 'ls /etc/zabbix/zabbix_agent2.conf.bak.*' >/dev/null || fail "기존 설정 백업"; ok "기존 설정 백업 생성"

echo "== 4. 추가 데이터(UserParameter) 연동 — README '추가 데이터 전달' 예시"
x "cat > /etc/zabbix/zabbix_agent2.d/custom.conf <<'EOF'
UserParameter=custom.echo[*],echo \"\$1\"
UserParameter=custom.app.status,echo '{\"version\":\"1.2.3\",\"queue\":7}'
EOF
systemctl restart zabbix-agent2; sleep 2"
[[ $(x "zabbix_get -s $AGENT_IP -k 'custom.echo[hello]'") == hello ]] || fail "custom.echo"; ok "custom.echo[hello] = hello"
[[ $(x "zabbix_get -s $AGENT_IP -k custom.app.status") == '{"version":"1.2.3","queue":7}' ]] || fail "custom.app.status"; ok "custom.app.status JSON 반환"
x 'zabbix_agent2 -t custom.echo[local]' | grep -q local || fail "zabbix_agent2 -t"; ok "zabbix_agent2 -t 로 로컬 테스트"

echo "== 모든 테스트 통과"
