# Zabbix Agent 2 설치 도구 (Ubuntu 26.04 / Zabbix 7.4)

Ubuntu 26.04 LTS 호스트에 **Zabbix agent2**를 설치하고 Zabbix 서버(7.4.16)에 연동하는 스크립트와 전체 설치 매뉴얼입니다.

| 파일 | 역할 |
|---|---|
| `install_agent2.sh [버전]` | 공식 저장소(repo.zabbix.com)를 등록하고 `zabbix-agent2`, `zabbix-get`을 설치합니다. 버전을 생략하면 **7.4**(7.4 계열 최신)를 설치합니다. |
| `configure_agent2.sh Server=… ServerActive=… Hostname=…` | `./zabbix_agent2.conf`의 세 값을 갱신합니다. 인자, 파일(`-f`), 대화형 입력을 모두 지원합니다. |
| `deploy_agent2.sh <에이전트 IP>` | 설정 파일을 `/etc/zabbix`에 복사하고 서비스를 enable·restart합니다. 이어서 `zabbix_agent2 -V`와 `zabbix_get … agent.ping`으로 검증합니다. |
| `zabbix_agent2.conf` | 공식 `zabbix-agent2 7.4.16` 패키지에서 추출한 기본 설정 원본입니다(수정 전 상태). |
| `test/` | WSL Docker에 Ubuntu 26.04(systemd) 컨테이너를 띄워 위 과정을 자동 검증합니다. |

---

## 1. 사전 요구사항

- 대상 OS는 **Ubuntu 26.04 LTS**(resolute)입니다. 스크립트가 `/etc/os-release`의 `VERSION_ID`를 읽으므로 22.04와 24.04에서도 그대로 동작합니다.
- `sudo` 권한과 `repo.zabbix.com`(HTTPS)에 대한 외부 접속이 필요합니다.
- 네트워크 방화벽은 다음 두 방향을 열어야 합니다.

| 방향 | 포트 | 용도 |
|---|---|---|
| Zabbix 서버(또는 프록시) → 에이전트 | **10050/tcp** | 패시브 체크(서버가 값을 요청) |
| 에이전트 → Zabbix 서버(또는 프록시) | **10051/tcp** | 액티브 체크, 자동 등록, `zabbix_sender` |

  `ufw`를 쓴다면 `sudo ufw allow from <Zabbix 서버 IP> to any port 10050 proto tcp`로 엽니다.
- 서버와 에이전트 버전: 서버가 7.4.16이면 에이전트도 7.4.x를 권장합니다. 에이전트가 서버보다 **낮거나 같은** 버전이면 호환됩니다.

## 2. 빠른 시작

```bash
git clone <이 저장소> zabbix-agent2-installer && cd zabbix-agent2-installer
chmod +x *.sh

sudo ./install_agent2.sh 7.4.16                       # 버전 생략 시 7.4 최신
./configure_agent2.sh Server=10.0.0.10 ServerActive=10.0.0.10 Hostname=web-01
sudo ./deploy_agent2.sh 10.0.0.21                     # 이 호스트(에이전트)의 IP
```

그다음 [4장](#4-zabbix-웹-ui에-호스트-등록)에 따라 웹 UI에 호스트를 등록합니다.

## 3. 단계별 설치

### 3.1 설치: `install_agent2.sh`

```bash
sudo ./install_agent2.sh            # 7.4 계열 최신 (현재 7.4.16)
sudo ./install_agent2.sh 7.4        # 위와 같음
sudo ./install_agent2.sh 7.4.16     # 정확히 7.4.16 고정 (같은 버전 중 가장 높은 리비전, 예: 1:7.4.16-2)
sudo ./install_agent2.sh 7.0        # 다른 LTS 계열
```

스크립트는 다음 순서로 동작합니다.
1. `zabbix-release_latest_<계열>+ubuntu<OS버전>_all.deb`를 받아 Zabbix 저장소를 등록합니다.
   (Ubuntu 26.04 + 7.4 기준 주소: `https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu26.04_all.deb`)
2. `apt-cache madison`으로 설치할 버전을 결정합니다. 저장소에 없는 버전을 지정하면 설치 가능한 버전 목록을 보여 주고 종료합니다.
3. `zabbix-agent2`와 점검용 `zabbix-get`을 설치합니다. 낮은 버전을 지정하면 다운그레이드도 허용합니다.

> Ubuntu 26.04 기본 저장소(universe)에도 `zabbix-agent2 1:7.0.22+dfsg`가 있습니다. Zabbix 저장소를 등록하면 버전이 더 높은 공식 7.4 패키지가 설치됩니다.
> 확인 명령: `apt-cache policy zabbix-agent2`

수동으로 설치하려면 다음과 같이 합니다.
```bash
wget https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu26.04_all.deb
sudo dpkg -i zabbix-release_latest_7.4+ubuntu26.04_all.deb
sudo apt update && sudo apt install -y zabbix-agent2 zabbix-get
```

### 3.2 설정값 반영: `configure_agent2.sh`

`./zabbix_agent2.conf`(공식 기본 설정)의 아래 세 값을 바꿉니다.

```
Server=<Zabbix 서버 IP>
ServerActive=<Zabbix 서버 IP>
Hostname=<웹 UI에 등록할 호스트명>
```

입력 방법은 세 가지입니다.
```bash
# ① 인자
./configure_agent2.sh Server=10.0.0.10 ServerActive=10.0.0.10 Hostname=web-01

# ② 파일 (위 형식 그대로, # 주석과 CRLF 허용)
cat > agent.env <<'EOF'
Server=10.0.0.10
ServerActive=10.0.0.10
Hostname=web-01
EOF
./configure_agent2.sh -f agent.env

# ③ 대화형 (ServerActive 를 비우면 Server 값을 사용)
./configure_agent2.sh

# 다른 파일을 수정하려면 마지막 인자로 경로를 지정
./configure_agent2.sh -f agent.env /path/to/zabbix_agent2.conf
```

각 값의 의미는 다음과 같습니다.

| 키 | 의미 | 예 |
|---|---|---|
| `Server` | 패시브 체크를 **요청할 수 있는** 서버·프록시 IP 목록입니다(허용 목록). 쉼표로 구분하고 CIDR도 쓸 수 있습니다. | `10.0.0.10`, `10.0.0.10,10.0.0.0/24` |
| `ServerActive` | 액티브 체크를 위해 에이전트가 **접속할** 서버 주소입니다. `host:port` 형식을 쓸 수 있고, HA 클러스터 노드는 `;`로 구분합니다. | `10.0.0.10`, `10.0.0.10:10051`, `zbx1;zbx2` |
| `Hostname` | 웹 UI의 **Host name**과 **글자 하나까지 같아야** 합니다. 대소문자도 구분합니다. 영문·숫자·공백·`.` `_` `-`만 쓸 수 있고 128자 이하여야 합니다. | `web-01` |

스크립트는 허용되지 않은 문자를 거부합니다. 반영한 뒤에는 각 키가 정확히 한 줄로 들어갔는지 스스로 점검합니다.

### 3.3 적용과 검증: `deploy_agent2.sh`

```bash
sudo ./deploy_agent2.sh 10.0.0.21          # 인자 생략 시 IP 를 물어봄
```

이 스크립트는 다음 명령을 차례로 실행합니다.
```bash
zabbix_agent2 -T -c ./zabbix_agent2.conf             # 설정 문법 검사 (실패하면 중단, 기존 설정 유지)
cp ./zabbix_agent2.conf /etc/zabbix/zabbix_agent2.conf   # 기존 파일은 .bak.<시각> 으로 보관
sudo systemctl enable --now zabbix-agent2
sudo systemctl restart zabbix-agent2                 # 이미 실행 중이면 이 단계가 있어야 새 설정이 반영됨
zabbix_agent2 -V
zabbix_get -s <에이전트 IP> -k agent.ping            # 결과 1 이면 정상 (최대 10초 재시도)
```

> **`zabbix_get`과 `Server` 허용 목록:** 에이전트는 `Server=`에 적힌 IP의 요청에만 응답합니다. 그래서 에이전트 호스트에서 자기 IP로 `zabbix_get`을 실행하면 출발지 IP가 에이전트 IP가 되고, `Server`가 서버 IP뿐이라면 거부됩니다. 이럴 때는 두 방법 중 하나를 씁니다.
> - Zabbix 서버에서 확인합니다(권장): `zabbix_get -s 10.0.0.21 -k agent.ping`
> - 에이전트에서 확인하려면 `Server=10.0.0.10,127.0.0.1`처럼 로컬 주소를 추가하고 `zabbix_get -s 127.0.0.1 -k agent.ping`을 실행합니다.

## 4. Zabbix 웹 UI에 호스트 등록

1. **Data collection → Hosts → Create host**로 들어갑니다.
2. **Host name**에 `Hostname=` 값과 똑같은 이름(예: `web-01`)을 넣습니다.
3. **Host groups**에서 `Linux servers` 등을 고릅니다.
4. **Interfaces → Add → Agent**를 고르고 IP에 에이전트 IP(예: `10.0.0.21`), Port에 `10050`을 넣습니다.
5. **Templates**에서 다음 중 하나를 고릅니다.
   - `Linux by Zabbix agent`: 패시브 방식입니다. 서버가 10050으로 접속합니다.
   - `Linux by Zabbix agent active`: 액티브 방식입니다. 에이전트가 10051로 접속하며, NAT나 방화벽 뒤에 있는 호스트에 적합합니다.
6. **Add**를 누릅니다. 1~2분 뒤 호스트 목록의 **Availability** 아이콘 `ZBX`가 초록색이면 정상입니다.

## 5. 기본 설정 파일(`zabbix_agent2.conf`)의 출처

저장소의 `zabbix_agent2.conf`는 공식 패키지 `zabbix-agent2 1:7.4.16-2+ubuntu26.04`의 `/etc/zabbix/zabbix_agent2.conf`를 그대로 꺼낸 것입니다. 다시 받거나 다른 버전의 파일이 필요하면 아래 방법 중 하나를 씁니다.

```bash
# A. 패키지에서 추출 (Docker, Ubuntu 26.04 컨테이너)
docker run --rm ubuntu:26.04 bash -c '
  apt-get update -qq && apt-get install -y -qq wget ca-certificates >/dev/null &&
  wget -q https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu26.04_all.deb &&
  dpkg -i zabbix-release_*.deb >/dev/null && apt-get update -qq &&
  cd /tmp && apt-get download -qq zabbix-agent2 &&
  dpkg-deb --fsys-tarfile zabbix-agent2_*.deb | tar -xO ./etc/zabbix/zabbix_agent2.conf' > zabbix_agent2.conf

# B. 공식 agent2 Docker 이미지에서 복사
#    주의: 이 이미지의 설정은 환경 변수 방식(Include 등)에 맞춰 바뀌어 있어 패키지 원본과 다를 수 있습니다.
docker create --name zbx-tmp zabbix/zabbix-agent2:ubuntu-7.4-latest
docker cp zbx-tmp:/etc/zabbix/zabbix_agent2.conf ./zabbix_agent2.conf && docker rm zbx-tmp

# C. 설치된 호스트라면 그대로 복사
cp /etc/zabbix/zabbix_agent2.conf ./zabbix_agent2.conf
```

설정 레퍼런스: <https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2>

---

## 6. 기본 정보 외 추가 데이터를 호스트에 전달·연동하는 방법

템플릿(`Linux by Zabbix agent`)이 기본으로 수집하는 CPU·메모리·디스크·네트워크 외에, 업무 고유의 데이터(애플리케이션 상태, 배치 결과, 큐 길이, 라이선스 만료일 등)를 Zabbix로 보내는 방법을 정리했습니다. 어떤 방법이 맞는지는 다음 표로 고릅니다.

| 상황 | 방법 | 데이터 흐름 |
|---|---|---|
| 명령이나 스크립트 출력을 주기적으로 수집 | **6.1 UserParameter** | 서버 → 에이전트 요청(패시브) 또는 에이전트 → 서버(액티브) |
| 방화벽 때문에 서버가 에이전트로 접속할 수 없음 | **6.2 액티브 체크** | 에이전트 → 서버 10051 |
| 배치·크론·앱이 **이벤트가 생긴 시점에** 값을 보냄 | **6.3 zabbix_sender + Trapper** | 호스트 → 서버 10051 (push) |
| JSON 한 번으로 여러 값을 받음 | **6.4 Dependent item + 전처리** | 마스터 아이템 1개 → 파생 아이템 N개 |
| 대상 개수가 변함(디렉터리, 큐, 서비스 목록) | **6.5 LLD(저수준 자동 발견)** | 발견 규칙 → 아이템 프로토타입 |
| 로그 파일의 특정 패턴 | **6.6 log[] / logrt[]** | 액티브 |
| DB·Docker·Redis 등 미들웨어 | **6.7 Agent2 플러그인** | 내장 키 사용 |
| 호스트를 자동으로 등록하고 역할별 템플릿 연결 | **6.8 HostMetadata + 자동 등록** | 에이전트 → 서버 |
| 설정 없이 임의 명령 실행 | **6.9 system.run (AllowKey)** | 보안상 최후의 수단 |
| 위치·담당자 같은 정적 정보 | **6.10 인벤토리·태그·매크로** | 웹 UI·API |

### 6.1 UserParameter: 사용자 정의 키

**1) 에이전트에 키를 정의합니다.** 메인 설정 파일은 건드리지 않고 include 디렉터리에 별도 파일을 만듭니다. 기본 설정에 `Include=/etc/zabbix/zabbix_agent2.d/*.conf`가 이미 들어 있습니다.

```bash
sudo tee /etc/zabbix/zabbix_agent2.d/custom.conf >/dev/null <<'EOF'
# 형식: UserParameter=<키>,<명령>         (출력의 첫 줄 / 전체가 값이 됨)
UserParameter=custom.app.status,systemctl is-active myapp
UserParameter=custom.queue.length,/opt/scripts/queue_len.sh

# 파라미터형: 키[*] 로 정의하고 명령에서 $1, $2 … 로 참조
UserParameter=custom.file.lines[*],wc -l < "$1"
UserParameter=custom.echo[*],echo "$1"

# JSON 을 한 번에 반환 (6.4 Dependent item 과 함께 사용)
UserParameter=custom.app.stats,/opt/scripts/app_stats.sh
EOF
sudo systemctl restart zabbix-agent2
```

명령은 `zabbix` 사용자 권한으로 실행됩니다. root 권한이 필요하면 `sudoers`에 해당 명령만 허용합니다.
```
# /etc/sudoers.d/zabbix  (visudo -f 로 편집)
zabbix ALL=(root) NOPASSWD: /opt/scripts/queue_len.sh
```
그다음 `UserParameter=custom.queue.length,sudo /opt/scripts/queue_len.sh`로 바꿉니다.

**2) 로컬과 원격에서 테스트합니다.**
```bash
zabbix_agent2 -t 'custom.echo[hello]'                     # 에이전트 프로세스 없이 로컬 평가
zabbix_get -s <에이전트 IP> -k 'custom.echo[hello]'       # 서버에서 실제 요청 (Server= 허용 필요)
```

**3) 웹 UI에서 아이템을 만듭니다.** **Data collection → Hosts → (호스트) → Items → Create item**에서 다음과 같이 넣습니다.
- Type: `Zabbix agent`(패시브) 또는 `Zabbix agent (active)`
- Key: `custom.queue.length`(파라미터형이면 `custom.file.lines[/var/log/app.log]`)
- Type of information: 숫자면 `Numeric (unsigned)`나 `Numeric (float)`, 문자열이면 `Character`나 `Text`
- Update interval: 예) `1m`

여러 호스트에 같은 키를 쓴다면 **템플릿**에 아이템을 만들고 그 템플릿을 호스트에 연결합니다.

**4) 트리거를 걸어 알림을 받습니다.** 예) `last(/web-01/custom.queue.length)>100`

주의할 점은 다음과 같습니다.
- 파라미터에 `\ ' " ` * ? [ ] { } ~ $ ! & ; ( ) < > | # @` 같은 특수문자를 허용하려면 `UnsafeUserParameters=1`이 필요합니다. 보안상 가능하면 쓰지 않습니다.
- 명령은 `Timeout`(기본 3초, 최대 30초) 안에 끝나야 합니다. 오래 걸리는 작업은 크론으로 결과를 파일에 쓰고 `vfs.file.contents[...]`로 읽거나, 6.3의 sender 방식을 씁니다.

### 6.2 액티브 체크(에이전트가 먼저 접속)

- `ServerActive=<서버 IP>`와 `Hostname=<웹 UI 호스트명>`이 정확해야 합니다.
- 아이템 Type을 `Zabbix agent (active)`로 만듭니다. UserParameter 키도 액티브로 수집할 수 있습니다.
- 에이전트가 서버에서 수집 목록을 받아(`RefreshActiveChecks`, 기본 5초) 값을 보냅니다. 서버에서 에이전트로 들어오는 10050 포트가 막혀 있어도 동작합니다.
- 액티브 아이템만 쓰는 호스트는 Interface를 비워도 됩니다. 다만 템플릿은 `Linux by Zabbix agent active`를 써야 합니다.

### 6.3 zabbix_sender + Zabbix trapper(호스트가 값을 push)

배치 성공 여부, 처리 건수, 배포 버전처럼 **이벤트가 생긴 시점의 값**을 보내기에 적합합니다.

**1) 웹 UI에서 아이템을 만듭니다.** Type `Zabbix trapper`, Key 예: `batch.daily.result`, Type of information `Numeric (unsigned)`로 만듭니다. 필요하면 *Allowed hosts*에 보내는 쪽 IP를 제한합니다.

**2) 호스트에서 보냅니다.**
```bash
sudo apt install -y zabbix-sender                       # 같은 Zabbix 저장소에 있음

# 단일 값
zabbix_sender -z <Zabbix 서버 IP> -s "web-01" -k batch.daily.result -o 1

# 에이전트 설정을 재사용 (ServerActive·Hostname 을 읽음, -s 생략 가능)
zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -k batch.daily.result -o 1

# 여러 값 한 번에 (파일: <호스트> <키> <값>,  "-" 는 설정 파일의 Hostname)
cat > /tmp/values.txt <<'EOF'
- batch.daily.result 1
- batch.daily.count 15230
- app.deploy.version "v2.3.1"
EOF
zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -i /tmp/values.txt
```
`processed: 3; failed: 0`이 나오면 성공입니다. `failed`가 있으면 호스트명·키 오타이거나 아이템이 trapper 타입이 아닌 경우입니다.

크론 예시입니다.
```
0 3 * * * root /opt/batch/run.sh && r=1 || r=0; zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -k batch.daily.result -o $r
```

### 6.4 Dependent item + 전처리: JSON 하나에서 여러 값 추출

스크립트가 `{"version":"1.2.3","queue":7,"errors":0}`를 출력한다면 다음과 같이 나눠 받습니다.
1. **마스터 아이템**을 만듭니다. Key `custom.app.stats`(6.1의 UserParameter), Type of information `Text`로 하고, 이력이 필요 없으면 History를 `0`으로 둡니다.
2. **Dependent item**을 만듭니다. Type `Dependent item`, Master item에 위 아이템을 고르고, Preprocessing에서 `JSONPath` → `$.queue`를 지정합니다. `$.errors`, `$.version`도 같은 방식으로 각각 만듭니다.
3. 결과적으로 에이전트 호출은 한 번이고 아이템은 N개가 됩니다. `vfs.file.contents`, `web.page.get`, HTTP agent 아이템 결과에도 같은 방법을 쓸 수 있습니다.

### 6.5 LLD(저수준 자동 발견): 개수가 바뀌는 대상

발견용 UserParameter가 JSON 배열을 반환하게 합니다.
```bash
UserParameter=custom.queue.discovery,ls /var/spool/myapp | jq -R '{"{#QUEUE}":.}' | jq -s .
UserParameter=custom.queue.size[*],ls /var/spool/myapp/$1 | wc -l
```
(`jq`가 필요합니다: `sudo apt install -y jq`)

웹 UI에서 **Discovery rules → Create discovery rule**을 열어 Key를 `custom.queue.discovery`로 정합니다. 그다음 **Item prototypes**에 Key `custom.queue.size[{#QUEUE}]`를 만듭니다. 큐가 추가되거나 삭제되면 아이템도 자동으로 생기거나 사라집니다.

### 6.6 로그 모니터링

에이전트가 로그 파일을 읽을 권한이 필요합니다(`sudo usermod -aG adm zabbix` 등).

웹 UI에서 Type `Zabbix agent (active)`(필수), Type of information `Log`로 아이템을 만들고 키를 다음과 같이 씁니다.
```
log[/var/log/myapp/app.log,"ERROR|FATAL",,,skip]
logrt["/var/log/myapp/app-.*\.log","ERROR",,,skip]      # 로테이션 파일
log.count[/var/log/myapp/app.log,"ERROR",,,skip]        # 건수만 숫자로
```
트리거 예: `find(/web-01/log[/var/log/myapp/app.log,"ERROR|FATAL",,,skip],,"regexp","FATAL")=1`

### 6.7 Agent2 플러그인(내장 미들웨어 수집)

Agent2에는 Docker, Redis, Memcached, Ceph, Modbus, MQTT, Oracle, Smart 등의 플러그인이 내장되어 있습니다. PostgreSQL·MongoDB·MSSQL 등은 별도 패키지로 설치합니다(`apt-cache search zabbix-agent2-plugin`).
```bash
sudo apt install -y zabbix-agent2-plugin-postgresql     # 예
ls /etc/zabbix/zabbix_agent2.d/plugins.d/               # 플러그인별 설정
```
사용 예시는 다음과 같습니다.
- Docker: `sudo usermod -aG docker zabbix`를 실행한 뒤 템플릿 `Docker by Zabbix agent 2`를 연결합니다.
- MySQL: 내장 플러그인입니다. 템플릿 `MySQL by Zabbix agent 2`를 연결하고 호스트 매크로 `{$MYSQL.DSN}`, `{$MYSQL.USER}`, `{$MYSQL.PASSWORD}`를 설정합니다.
- Redis: `Redis by Zabbix agent 2`를 연결합니다. 접속 정보는 `plugins.d/redis.conf`의 Sessions나 매크로로 지정합니다.

DB 계정에는 모니터링에 필요한 **최소 권한**만 줍니다.

### 6.8 HostMetadata + 자동 등록(Autoregistration)

에이전트가 처음 접속할 때 메타데이터를 보내면, 서버가 자동으로 호스트를 만들고 템플릿·그룹을 연결합니다.
```
# /etc/zabbix/zabbix_agent2.d/autoreg.conf
HostMetadata=linux web prod
# 또는 명령 결과로: HostMetadataItem=system.uname
```
웹 UI에서 **Alerts → Actions → Autoregistration actions → Create action**을 열고 다음과 같이 설정합니다.
- Conditions: `Host metadata` *contains* `web`
- Operations: `Add host`, `Add to host groups: Web servers`, `Link templates: Linux by Zabbix agent active`, 필요하면 `Add host tags`

이 방식은 `ServerActive`와 `Hostname`이 설정되어 있어야 동작합니다. 대량 배포할 때 웹 UI에서 호스트를 하나씩 등록하는 수고를 덜어 줍니다.

### 6.9 system.run (가급적 쓰지 않음)

Agent2는 기본적으로 `system.run`을 막아 둡니다. 꼭 필요하면 **특정 명령만** 허용합니다.
```
AllowKey=system.run[/opt/scripts/health.sh]
DenyKey=system.run[*]
```
웹 UI 아이템 키에는 `system.run[/opt/scripts/health.sh]`를 넣습니다. `AllowKey=system.run[*]`는 원격에서 임의 명령을 실행할 수 있게 하므로 **쓰지 않습니다.** 대신 6.1의 UserParameter를 씁니다.

### 6.10 정적 정보: 인벤토리·태그·매크로

- **Host inventory**는 호스트 → Inventory 탭에서 `Manual`이나 `Automatic`으로 둡니다. `Automatic`이면 아이템 설정의 *Populates host inventory field*로 수집값(예: `system.sw.os`)이 인벤토리에 채워집니다.
- **Tags**에는 `env=prod`, `service=payment`, `owner=team-a` 같은 값을 붙여 필터, 대시보드, 알림 조건에 씁니다.
- **User macros**는 `{$QUEUE.MAX}=100`처럼 임계값을 호스트별로 덮어쓸 때 씁니다. 트리거에서는 `last(/web-01/custom.queue.length)>{$QUEUE.MAX}`처럼 참조합니다.
- 대량으로 반영하려면 Zabbix API(`host.update`, `usermacro.create`)를 씁니다.

---

## 7. 문제 해결

| 증상 | 확인 |
|---|---|
| `zabbix_get`이 빈 값이나 `connection reset by peer`를 돌려주고, 에이전트 로그에 `connection from "<IP>" rejected`가 남음 | `Server=`에 요청한 호스트의 IP가 없습니다(3.3 참고). |
| `zabbix_get`이 timeout됨 | 방화벽에서 10050/tcp가 막혀 있거나 서비스가 내려가 있습니다. `systemctl status zabbix-agent2`, `ss -ltnp \| grep 10050`으로 확인합니다. |
| 웹 UI의 `ZBX`가 빨간색 | Interface IP와 포트, 서버에서 실행한 `zabbix_get` 결과를 확인합니다. |
| 액티브 아이템이 *Not supported*이거나 값이 없음 | 로그에 `host [xxx] not found`가 있으면 `Hostname`과 웹 UI Host name이 다릅니다. |
| 설정을 바꿨는데 반영되지 않음 | `sudo systemctl restart zabbix-agent2`를 실행했는지 확인합니다. 문법은 `zabbix_agent2 -T`로 검사합니다. |
| 로그 확인 | `tail -f /var/log/zabbix/zabbix_agent2.log`, `journalctl -u zabbix-agent2 -e` |
| UserParameter가 *Not supported* | `zabbix_agent2 -t <키>`로 오류를 확인합니다. `zabbix` 사용자 권한과 Timeout을 점검합니다. |

설정을 되돌리려면 `deploy_agent2.sh`가 남긴 `/etc/zabbix/zabbix_agent2.conf.bak.<시각>`을 복원하고 restart합니다.

제거 방법은 다음과 같습니다.
```bash
sudo systemctl disable --now zabbix-agent2
sudo apt purge -y zabbix-agent2 zabbix-get zabbix-release
```

## 8. 테스트(WSL Docker)

```bash
# WSL Ubuntu 에서, 저장소 루트
bash test/run_test.sh
```

`test/Dockerfile`은 systemd가 PID 1인 Ubuntu 26.04 컨테이너를 만듭니다(`--privileged --cgroupns=host`). `run_test.sh`는 그 안에서 다음을 차례로 검증합니다.
1. 잘못된 버전 형식을 거부하는지, `7.4.15`를 고정 설치할 수 있는지, 버전을 생략하면 7.4 최신(7.4.16)으로 업그레이드되는지, `zabbix_get`이 설치되는지
2. 잘못된 Hostname을 거부하는지, `-f` 파일 입력(CRLF 포함)·대화형 입력·인자 입력이 반영되는지
3. `deploy_agent2.sh <컨테이너 IP>`로 `/etc` 반영, enabled·active 상태, `agent.ping = 1`, `agent.hostname` 일치, 백업 파일 생성을 확인하는지
4. 6.1의 UserParameter(`custom.echo[*]`, JSON 반환)를 `zabbix_get`과 `zabbix_agent2 -t`로 조회할 수 있는지

테스트가 끝나거나 실패하면 trap이 컨테이너와 테스트 이미지를 **항상 삭제**합니다.

2026-11-06 실행 결과: Ubuntu 26.04.1 LTS에서 zabbix_agent2 7.4.16으로 모든 항목이 PASS였습니다.
