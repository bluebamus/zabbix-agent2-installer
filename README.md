# Zabbix Agent 2 설치 도구 (Ubuntu 26.04 / Zabbix 7.4)

Ubuntu 26.04 LTS 호스트에 **Zabbix agent2**를 설치하고 Zabbix 서버(7.4.16)에 연동하는 스크립트와 전체 설치 매뉴얼입니다.

폴더 번호가 곧 작업 순서입니다. 모든 명령은 **저장소 루트**에서 실행합니다.

```
zabbix-agent2-installer/
├── 1_install/
│   └── install_agent2.sh        # [1단계] 저장소 등록 + agent2·zabbix-get 설치
├── 2_configure/
│   ├── configure_agent2.sh      # [2단계] Server / ServerActive / Hostname / HostMetadata(선택) 반영
│   └── zabbix_agent2.conf       #         공식 7.4.16 기본 설정 원본 (이 파일이 갱신됨)
├── 3_deploy/
│   └── deploy_agent2.sh         # [3단계] /etc 복사·서비스 기동·agent.ping 검증
├── 4_test/
│   ├── Dockerfile               # [4단계] Ubuntu 26.04 + systemd 테스트 이미지
│   └── run_test.sh              #         WSL Docker 자동 검증
└── README.md
```

| 단계 | 파일 | 역할 |
|---|---|---|
| 1 | `1_install/install_agent2.sh [버전]` | 공식 저장소(repo.zabbix.com)를 등록하고 `zabbix-agent2`, `zabbix-get`을 설치합니다. 버전을 생략하면 **7.4**(7.4 계열 최신)를 설치합니다. |
| 2 | `2_configure/configure_agent2.sh Server=… ServerActive=… Hostname=… [HostMetadata=…]` | `2_configure/zabbix_agent2.conf`의 값을 갱신합니다(`HostMetadata`는 선택). 인자, 파일(`-f`), 대화형 입력을 모두 지원합니다. |
| 3 | `3_deploy/deploy_agent2.sh <에이전트 IP>` | 2단계에서 갱신한 설정 파일을 `/etc/zabbix`에 복사하고 서비스를 enable·restart합니다. 이어서 `zabbix_agent2 -V`와 `zabbix_get … agent.ping`으로 검증합니다. |
| 4 | `4_test/run_test.sh` | WSL Docker에 Ubuntu 26.04(systemd) 컨테이너를 띄워 1~3단계를 자동 검증합니다. |

스크립트는 자기 위치를 기준으로 설정 파일을 찾으므로, 다른 디렉터리에서 실행해도 기본 경로(`2_configure/zabbix_agent2.conf`)를 사용합니다.

---

## 1. 사전 요구사항

- 대상 OS는 **Ubuntu 26.04 LTS**(resolute)입니다. 스크립트가 `/etc/os-release`의 `VERSION_ID`를 읽으므로 22.04와 24.04에서도 그대로 동작합니다.
- `sudo` 권한과 `repo.zabbix.com`(HTTPS)에 대한 외부 접속이 필요합니다.
- 네트워크 방화벽은 다음 두 방향을 열어야 합니다.

| 방향 | 포트 | 용도 |
|---|---|---|
| Zabbix 서버(또는 프록시) → 에이전트 | **10050/tcp** | 패시브 체크(서버가 값을 요청) |
| 에이전트 → Zabbix 서버(또는 프록시) | **10051/tcp** | 액티브 체크, 자동 등록, `zabbix_sender`. 수집을 패시브로만 하더라도 **자동 등록을 쓰면 필요**합니다([6.8](#68-hostmetadata--자동-등록autoregistration)). |

  `ufw`를 쓴다면 `sudo ufw allow from <Zabbix 서버 IP> to any port 10050 proto tcp`로 엽니다.
- 서버와 에이전트 버전: 서버가 7.4.16이면 에이전트도 7.4.x를 권장합니다. 에이전트가 서버보다 **낮거나 같은** 버전이면 호환됩니다.

## 2. 빠른 시작

```bash
git clone <이 저장소> zabbix-agent2-installer && cd zabbix-agent2-installer
chmod +x [1-4]_*/*.sh

sudo ./1_install/install_agent2.sh 7.4.16                       # 버전 생략 시 7.4 최신
./2_configure/configure_agent2.sh Server=10.0.0.10 ServerActive=10.0.0.10:10051 Hostname=mysql-prod-01 HostMetadata=linux,mysql,prod
sudo ./3_deploy/deploy_agent2.sh 10.0.0.21                     # 이 호스트(에이전트)의 IP
```

그다음 [4장](#4-zabbix-웹-ui에-호스트-등록)에 따라 웹 UI에 호스트를 등록합니다.

## 3. 단계별 설치

### 3.1 [1단계] 설치: `1_install/install_agent2.sh`

```bash
sudo ./1_install/install_agent2.sh            # 7.4 계열 최신 (현재 7.4.16)
sudo ./1_install/install_agent2.sh 7.4        # 위와 같음
sudo ./1_install/install_agent2.sh 7.4.16     # 정확히 7.4.16 고정 (같은 버전 중 가장 높은 리비전, 예: 1:7.4.16-2)
sudo ./1_install/install_agent2.sh 7.0        # 다른 LTS 계열
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

### 3.2 [2단계] 설정값 반영: `2_configure/configure_agent2.sh`

`2_configure/zabbix_agent2.conf`(공식 기본 설정)의 아래 값을 바꿉니다. `HostMetadata`는 **선택** 항목입니다.

```
Server=<Zabbix 서버 IP>
ServerActive=<Zabbix 서버 IP>[:포트]
Hostname=<웹 UI에 등록할 호스트명>
HostMetadata=<자동 등록용 메타데이터>      # 선택
```

입력 방법은 세 가지입니다.
```bash
# ① 인자
./2_configure/configure_agent2.sh Server=10.0.0.10 ServerActive=10.0.0.10:10051 \
    Hostname=mysql-prod-01 HostMetadata=linux,mysql,prod

# ② 파일 (위 형식 그대로, # 주석과 CRLF 허용)
cat > agent.env <<'EOF'
Server=10.0.0.10
ServerActive=10.0.0.10:10051
Hostname=mysql-prod-01
HostMetadata=linux,mysql,prod
EOF
./2_configure/configure_agent2.sh -f agent.env

# ③ 대화형 (ServerActive 를 비우면 Server 값을 사용, HostMetadata 를 비우면 생략)
./2_configure/configure_agent2.sh

# 다른 파일을 수정하려면 마지막 인자로 경로를 지정
./2_configure/configure_agent2.sh -f agent.env /path/to/zabbix_agent2.conf
```

각 값의 의미는 다음과 같습니다.

| 키 | 의미 | 예 |
|---|---|---|
| `Server` | 패시브 체크를 **요청할 수 있는** 서버·프록시 IP 목록입니다(허용 목록). 쉼표로 구분하고 CIDR도 쓸 수 있습니다. | `10.0.0.10`, `10.0.0.10,10.0.0.0/24` |
| `ServerActive` | 액티브 체크를 위해 에이전트가 **접속할** 서버 주소입니다. `host:port` 형식을 쓸 수 있고, HA 클러스터 노드는 `;`로 구분합니다. | `10.0.0.10`, `10.0.0.10:10051`, `zbx1;zbx2` |
| `Hostname` | 웹 UI의 **Host name**과 **글자 하나까지 같아야** 합니다. 대소문자도 구분합니다. 영문·숫자·공백·`.` `_` `-`만 쓸 수 있고 128자 이하여야 합니다. | `mysql-prod-01` |
| `HostMetadata` (선택) | [자동 등록](#68-hostmetadata--자동-등록autoregistration) 때 서버로 보내는 문자열입니다. 서버의 자동 등록 Action이 이 값의 포함 여부로 그룹·템플릿을 정합니다. 영문·숫자·공백·`.` `,` `:` `;` `_` `=` `@` `/` `-`만 쓸 수 있고 2034자 이하여야 합니다. | `linux,mysql,prod` |

스크립트는 허용되지 않은 문자를 거부합니다. 반영한 뒤에는 입력한 각 키가 정확히 한 줄로 들어갔는지 스스로 점검합니다.

`HostMetadata`는 이렇게 동작합니다.
- 기본 설정 파일에는 `# HostMetadata=`로 주석 처리되어 있습니다. 값을 주면 주석이 풀리면서 `HostMetadata=<값>`이 됩니다.
- 인자나 파일에서 이 항목을 빼면 기존 값을 그대로 둡니다. 그래서 다른 값만 고칠 때 이전 메타데이터가 지워지지 않습니다.
- 질문을 거쳐 값을 받는 것은 **아무 인자도 없이 실행한 대화형 모드**일 때뿐입니다. 일부 값만 인자로 준 자동화 실행은 입력을 기다리며 멈추지 않습니다.

#### `ServerActive` 값 고르기 (패시브만 쓸 때도 포함)

`ServerActive`는 액티브 체크와 자동 등록에 쓰는 **에이전트 → 서버 연결**입니다. 수집 방식(패시브·액티브)은 이 값이 아니라 호스트에 연결한 **템플릿**이 정합니다. 그래서 패시브로만 감시하더라도 이 값을 꼭 지울 필요는 없습니다.

| `ServerActive` 값 | 동작 | 쓸 때 |
|---|---|---|
| 실제 서버 주소 (예: `10.0.0.10:10051`) **권장** | 자동 등록이 동작하고 패시브·액티브 템플릿을 모두 쓸 수 있습니다. | 대부분의 경우. 패시브 감시 + 자동 등록도 이 설정입니다. |
| `127.0.0.1` (공식 기본값 그대로) | 패시브는 정상입니다. 액티브 연결이 실패한 로그만 남고 자동 등록은 일어나지 않습니다. | 문제는 없지만 얻는 것도 없습니다. |
| 주석 처리 (`# ServerActive=…`) | 액티브 기능이 완전히 꺼집니다("If this parameter is not specified, active checks are disabled."). 로그가 깔끔합니다. | 10051 아웃바운드가 정책상 금지일 때, 의도치 않은 자동 등록을 막고 싶을 때 |

기본값 `127.0.0.1`을 그대로 둔 공식 agent2 7.4를 45초 동안 실행해 확인했습니다. 에이전트는 계속 정상 동작했고 `agent.ping`도 `1`이었습니다. 로그에는 다음 두 줄만 남았습니다.
```
active check configuration update from host [mysql-prod-01] started to fail
cannot connect to [127.0.0.1:10051]: dial tcp :0->127.0.0.1:10051: connect: connection refused
```

주석 처리는 스크립트 옵션이 아니라 직접 합니다. 스크립트에 `ServerActive`를 비워서 주면 `Server` 값이 대신 들어가기 때문입니다.
```bash
./2_configure/configure_agent2.sh Server=10.0.0.10 ServerActive=10.0.0.10 Hostname=mysql-prod-01
sed -i 's/^ServerActive=/# ServerActive=/' 2_configure/zabbix_agent2.conf
```
이 상태에서 `configure_agent2.sh`를 다시 실행하면 `반영 실패: ServerActive`가 나며 멈춥니다. 활성화된 `ServerActive=` 줄이 없기 때문입니다. 다시 실행하기 전에 주석을 먼저 풀어 주세요. 이렇게 액티브를 끈 경우에는 `HostMetadata`가 쓰이지 않습니다. 자동으로 추가하려면 [6.11 네트워크 디스커버리](#611-네트워크-디스커버리-serveractive-없이-서버가-찾아서-등록)를 씁니다.

### 3.3 [3단계] 적용과 검증: `3_deploy/deploy_agent2.sh`

```bash
sudo ./3_deploy/deploy_agent2.sh 10.0.0.21          # 인자 생략 시 IP 를 물어봄
```

**입력할 IP는 에이전트 IP입니다.** 지금 이 스크립트를 실행하고 있는 호스트(agent2를 설치한 서버)의 IP이며, Zabbix 서버 IP(`Server=` 값)가 아닙니다. 스크립트는 에이전트 호스트에서 실행되고, 마지막 단계에서 이 IP로 `agent.ping`을 보내 에이전트가 응답하는지 확인합니다.

이 스크립트는 다음 명령을 차례로 실행합니다.
```bash
zabbix_agent2 -T -c 2_configure/zabbix_agent2.conf             # 설정 문법 검사 (실패하면 중단, 기존 설정 유지)
cp 2_configure/zabbix_agent2.conf /etc/zabbix/zabbix_agent2.conf # 기존 파일은 .bak.<시각> 으로 보관
sudo systemctl enable --now zabbix-agent2
sudo systemctl restart zabbix-agent2                 # 이미 실행 중이면 이 단계가 있어야 새 설정이 반영됨
zabbix_agent2 -V
zabbix_get -s <에이전트 IP> -k agent.ping            # 결과 1 이면 정상 (최대 10초 재시도)
```

> **`zabbix_get`과 `Server` 허용 목록:** 에이전트는 `Server=`에 적힌 IP의 요청에만 응답합니다. 그래서 에이전트 호스트에서 자기 IP로 `zabbix_get`을 실행하면 출발지 IP가 에이전트 IP가 되고, `Server`가 서버 IP뿐이라면 거부됩니다. 이럴 때는 두 방법 중 하나를 씁니다.
> - Zabbix 서버에서 확인합니다(권장): `zabbix_get -s 10.0.0.21 -k agent.ping`
> - 에이전트에서 확인하려면 `Server=10.0.0.10,127.0.0.1`처럼 로컬 주소를 추가하고 `zabbix_get -s 127.0.0.1 -k agent.ping`을 실행합니다.
>
> 이 때문에 `Server=10.0.0.10`(서버 IP만)으로 설정한 뒤 `deploy_agent2.sh 10.0.0.21`을 실행하면 **5단계 `agent.ping` 확인이 실패하고 종료 코드 1로 끝날 수 있습니다.** 이 경우 설정 복사와 서비스 기동(1~4단계)은 이미 끝난 상태입니다. 따라서 설치 실패가 아니라 **확인 방법의 문제**입니다. 위의 두 방법 중 하나로 다시 확인하세요. 에이전트에서 바로 확인하려면 다음과 같이 합니다.
> ```bash
> ./2_configure/configure_agent2.sh Server=10.0.0.10,127.0.0.1 ServerActive=10.0.0.10:10051 Hostname=mysql-prod-01
> sudo ./3_deploy/deploy_agent2.sh 127.0.0.1
> ```
> `127.0.0.1`을 `Server`에 추가했더라도 대상은 **`127.0.0.1`** 로 주어야 합니다. 에이전트 IP(`10.0.0.21`)로 보내면 출발지가 그 IP가 되어 여전히 거부됩니다.
> Ubuntu 26.04 + agent2 7.4.16에서 확인한 결과는 다음과 같습니다.
>
> | `Server=` | 실행 | 결과 |
> |---|---|---|
> | `10.0.0.10` | `zabbix_get -s <에이전트 IP>` | 거부 (`Connection reset by peer`) |
> | `10.0.0.10,127.0.0.1` | `zabbix_get -s 127.0.0.1` | `1` |
> | `10.0.0.10,127.0.0.1` | `zabbix_get -s <에이전트 IP>` | 거부 |

## 4. Zabbix 웹 UI에 호스트 등록

1. **Data collection → Hosts → Create host**로 들어갑니다.
2. **Host name**에 `Hostname=` 값과 똑같은 이름(예: `web-01`)을 넣습니다.
3. **Host groups**에서 `Linux servers` 등을 고릅니다.
4. **Interfaces → Add → Agent**를 고르고 IP에 에이전트 IP(예: `10.0.0.21`), Port에 `10050`을 넣습니다.
5. **Templates**에서 다음 중 하나를 고릅니다.
   - `Linux by Zabbix agent`: 패시브 방식입니다. 서버가 10050으로 접속합니다.
   - `Linux by Zabbix agent active`: 액티브 방식입니다. 에이전트가 10051로 접속하며, NAT나 방화벽 뒤에 있는 호스트에 적합합니다.

호스트가 많다면 직접 등록하는 대신 자동으로 추가하는 방법이 있습니다. `ServerActive`를 켜 둔 경우에는 [6.8 자동 등록](#68-hostmetadata--자동-등록autoregistration)을 쓰고, 패시브로 감시할 수도 있습니다. `ServerActive`를 끈 경우에는 [6.11 네트워크 디스커버리](#611-네트워크-디스커버리-serveractive-없이-서버가-찾아서-등록)를 씁니다.
6. **Add**를 누릅니다. 1~2분 뒤 호스트 목록의 **Availability** 아이콘 `ZBX`가 초록색이면 정상입니다.

## 5. 기본 설정 파일(`zabbix_agent2.conf`)의 출처

저장소의 `2_configure/zabbix_agent2.conf`는 공식 패키지 `zabbix-agent2 1:7.4.16-2+ubuntu26.04`의 `/etc/zabbix/zabbix_agent2.conf`를 그대로 꺼낸 것입니다. 다시 받거나 다른 버전의 파일이 필요하면 아래 방법 중 하나를 씁니다.

```bash
# A. 패키지에서 추출 (Docker, Ubuntu 26.04 컨테이너)
docker run --rm ubuntu:26.04 bash -c '
  apt-get update -qq && apt-get install -y -qq wget ca-certificates >/dev/null &&
  wget -q https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu26.04_all.deb &&
  dpkg -i zabbix-release_*.deb >/dev/null && apt-get update -qq &&
  cd /tmp && apt-get download -qq zabbix-agent2 &&
  dpkg-deb --fsys-tarfile zabbix-agent2_*.deb | tar -xO ./etc/zabbix/zabbix_agent2.conf' > 2_configure/zabbix_agent2.conf

# B. 공식 agent2 Docker 이미지에서 복사
#    주의: 이 이미지의 설정은 환경 변수 방식(Include 등)에 맞춰 바뀌어 있어 패키지 원본과 다를 수 있습니다.
docker create --name zbx-tmp zabbix/zabbix-agent2:ubuntu-7.4-latest
docker cp zbx-tmp:/etc/zabbix/zabbix_agent2.conf ./2_configure/zabbix_agent2.conf && docker rm zbx-tmp

# C. 설치된 호스트라면 그대로 복사
cp /etc/zabbix/zabbix_agent2.conf ./2_configure/zabbix_agent2.conf
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
| 호스트를 자동으로 등록하고 역할별 템플릿 연결 | **6.8 HostMetadata + 자동 등록** | 에이전트 → 서버 10051 (등록 후 수집은 패시브도 가능) |
| `ServerActive`를 끈 상태에서 자동으로 추가 | **6.11 네트워크 디스커버리** | 서버 → 에이전트 10050 (스캔) |
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

**동작 방식과 패시브 감시.** 자동 등록 요청은 에이전트가 `ServerActive`로 액티브 체크 목록을 요청할 때 함께 보내집니다(10051). 이 요청은 재시작 직후 한 번 보내고, 그 뒤로는 `RefreshActiveChecks` 주기로 반복합니다. 그래서 **`ServerActive`가 실제 서버를 가리켜야** 자동 등록이 일어납니다. 주석 처리하거나 기본값 `127.0.0.1`로 두면 요청이 서버에 닿지 않습니다. 반면 **등록된 뒤의 수집 방식은 Action에서 연결하는 템플릿이 정하므로 패시브로 감시할 수 있습니다.** 공식 문서에도 "Active agent autoregistration also supports the monitoring of added hosts with passive checks."라고 적혀 있습니다.
- 서버는 등록할 때 에이전트 인터페이스를 함께 만듭니다. IP는 `HostInterface`·`HostInterfaceItem` 값이 있으면 그것을, 없으면 접속해 온 IP를 씁니다. 포트는 `ListenPort`, 없으면 10050입니다. 따라서 패시브 템플릿은 별도 설정 없이 동작합니다.
- 패시브로 감시하려면 방화벽에서 **10051(등록)과 10050(수집)이 둘 다** 열려 있어야 합니다.

**1) 에이전트에 메타데이터를 넣습니다.** 2단계 스크립트로 바로 넣을 수 있습니다.
```bash
./2_configure/configure_agent2.sh Server=10.0.0.10 ServerActive=10.0.0.10:10051 \
    Hostname=mysql-prod-01 HostMetadata=linux,mysql,prod
sudo ./3_deploy/deploy_agent2.sh <에이전트 IP>
```
고정 문자열 대신 명령 결과를 보내려면 `HostMetadataItem=system.uname`을 씁니다. `HostMetadata`가 비어 있을 때만 사용됩니다.

> 같은 키를 메인 설정과 `zabbix_agent2.d/*.conf`에 **함께 넣지 마세요.** 한쪽에서만 정의합니다.

**2) 서버에 자동 등록 Action을 만듭니다.** 웹 UI에서 **Alerts → Actions → Autoregistration actions → Create action**을 열고, 메타데이터의 각 단어마다 Action을 하나씩 만들면 역할별로 따로 처리됩니다.

| Action | Conditions | Operations |
|---|---|---|
| Linux 공통 | `Host metadata` *contains* `linux` | `Add host`, `Add to host groups: Linux servers`, `Link templates: Linux by Zabbix agent`(패시브) **또는** `Linux by Zabbix agent active`(액티브) 중 하나 |
| MySQL | `Host metadata` *contains* `mysql` | `Add to host groups: Databases`, `Link templates: MySQL by Zabbix agent 2` |
| 운영 환경 | `Host metadata` *contains* `prod` | `Add host tags: env=prod` (필요하면 알림 대상 그룹 연결) |

`linux,mysql,prod`를 보낸 `mysql-prod-01`에는 세 Action이 모두 적용됩니다. 그 결과 호스트가 만들어지고 Linux와 MySQL 템플릿, `env=prod` 태그가 붙습니다. MySQL 템플릿은 접속용 호스트 매크로(`{$MYSQL.DSN}` 등, 6.7)를 따로 넣어야 값을 수집합니다.

메타데이터에 `mysql`과 `mysql8`처럼 서로를 포함하는 단어가 있으면 *contains* 조건이 둘 다에 걸립니다. 이럴 때는 단어를 겹치지 않게 짓거나 *matches* 정규식 조건(예: `(^|,)mysql(,|$)`)을 씁니다.

이 방식은 `ServerActive`가 **실제 서버 주소**로, `Hostname`이 원하는 호스트명으로 설정되어 있어야 동작합니다. 대량 배포할 때 웹 UI에서 호스트를 하나씩 등록하는 수고를 덜어 줍니다. `ServerActive`를 꺼야 하는 환경이라면 [6.11 네트워크 디스커버리](#611-네트워크-디스커버리-serveractive-없이-서버가-찾아서-등록)를 씁니다.

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

### 6.11 네트워크 디스커버리: `ServerActive` 없이 서버가 찾아서 등록

에이전트에서 서버로 나가는 연결(10051)을 쓸 수 없거나 `ServerActive`를 꺼 둔 환경에서 쓰는 방법입니다. 이때는 반대로 **서버가 IP 대역을 스캔해** 에이전트를 찾고 호스트를 만듭니다. 이 방식은 `HostMetadata`를 쓰지 않습니다. 역할은 **에이전트에 물어본 키의 값**으로 구분합니다.

**1) 에이전트에 역할을 알려 주는 키를 둡니다.** (6.1 UserParameter)
```bash
sudo tee /etc/zabbix/zabbix_agent2.d/role.conf >/dev/null <<'EOF'
UserParameter=custom.role,echo linux,mysql,prod
EOF
sudo systemctl restart zabbix-agent2
```
에이전트의 `Server=`에는 스캔하는 서버(또는 프록시)의 IP가 들어 있어야 합니다.

**2) 디스커버리 규칙을 만듭니다.** **Data collection → Discovery → Create discovery rule**에서 다음과 같이 설정합니다.
- IP range: `10.0.0.1-254`, Update interval: 예) `1h`
- Checks: `Zabbix agent`, Port `10050`, Key `custom.role`
- Device uniqueness criteria: `IP address`
- Host name: `DNS name` 또는 `IP address`. 에이전트의 Hostname을 그대로 쓰고 싶으면 `system.hostname` 체크를 하나 더 두고 그 값을 고릅니다.

**3) 디스커버리 Action을 만듭니다.** **Alerts → Actions → Discovery actions → Create action**에서 설정합니다.

| Action | Conditions | Operations |
|---|---|---|
| Linux 공통 | `Discovery status` = `Up`, `Received value` *contains* `linux` | `Add host`, `Add to host groups: Linux servers`, `Link templates: Linux by Zabbix agent` |
| MySQL | `Received value` *contains* `mysql` | `Add to host groups: Databases`, `Link templates: MySQL by Zabbix agent 2` |

자동 등록(6.8)과 비교하면 다음과 같습니다.

| | 자동 등록 (6.8) | 네트워크 디스커버리 (6.11) |
|---|---|---|
| 누가 먼저 연결하나 | 에이전트 → 서버 10051 | 서버 → 에이전트 10050 (스캔) |
| `ServerActive` | 실제 서버 주소 필요 | 필요 없음 |
| 역할 구분 | `HostMetadata` | 체크 키의 반환값 (`Received value`) |
| 반영 속도 | 에이전트 기동 직후 | 스캔 주기(Update interval)마다 |
| 주의 | — | 스캔 대역이 넓으면 서버 부하가 커집니다. 디스커버리의 Zabbix agent 체크는 암호화 없이 질의합니다. |

> 6.11의 메뉴 이름과 조건 이름(`Received value` 등)은 Zabbix 7.4 웹 UI 기준입니다. 이 저장소의 테스트는 실제 Zabbix 서버로 검증하지 않았습니다.

---

## 7. 문제 해결

| 증상 | 확인 |
|---|---|
| `zabbix_get`이 빈 값이나 `connection reset by peer`를 돌려주고, 에이전트 로그에 `connection from "<IP>" rejected`가 남음 | `Server=`에 요청한 호스트의 IP가 없습니다(3.3 참고). |
| `zabbix_get`이 timeout됨 | 방화벽에서 10050/tcp가 막혀 있거나 서비스가 내려가 있습니다. `systemctl status zabbix-agent2`, `ss -ltnp \| grep 10050`으로 확인합니다. |
| 웹 UI의 `ZBX`가 빨간색 | Interface IP와 포트, 서버에서 실행한 `zabbix_get` 결과를 확인합니다. |
| 액티브 아이템이 *Not supported*이거나 값이 없음 | 로그에 `host [xxx] not found`가 있으면 `Hostname`과 웹 UI Host name이 다릅니다. |
| `deploy_agent2.sh` 5단계 `agent.ping`만 실패하고 서비스는 active | `Server=`에 에이전트 자신의 IP가 없어서입니다. 설치는 끝난 상태입니다. 서버에서 확인하거나 `127.0.0.1`을 추가해 다시 확인합니다(3.3). |
| 자동 등록으로 호스트가 생기지 않음 | `ServerActive`가 실제 서버를 가리키는지(주석이나 `127.0.0.1`이 아닌지), 10051 아웃바운드가 열려 있는지, Autoregistration action의 조건이 `HostMetadata`와 맞는지 확인합니다. |
| 에이전트 로그에 `cannot connect to [127.0.0.1:10051] ... connection refused`가 남음 | `ServerActive`가 기본값 `127.0.0.1`입니다. 패시브 수집에는 영향이 없습니다. 실제 서버 주소로 바꾸거나, 액티브를 쓰지 않으면 주석 처리합니다(3.2). |
| 설정을 바꿨는데 반영되지 않음 | `sudo systemctl restart zabbix-agent2`를 실행했는지 확인합니다. 문법은 `zabbix_agent2 -T`로 검사합니다. |
| 로그 확인 | `tail -f /var/log/zabbix/zabbix_agent2.log`, `journalctl -u zabbix-agent2 -e` |
| UserParameter가 *Not supported* | `zabbix_agent2 -t <키>`로 오류를 확인합니다. `zabbix` 사용자 권한과 Timeout을 점검합니다. |

설정을 되돌리려면 `3_deploy/deploy_agent2.sh`가 남긴 `/etc/zabbix/zabbix_agent2.conf.bak.<시각>`을 복원하고 restart합니다.

제거 방법은 다음과 같습니다.
```bash
sudo systemctl disable --now zabbix-agent2
sudo apt purge -y zabbix-agent2 zabbix-get zabbix-release
```

## 8. [4단계] 테스트(WSL Docker): `4_test/`

```bash
# WSL Ubuntu 에서, 저장소 루트
bash 4_test/run_test.sh
```

`4_test/Dockerfile`은 systemd가 PID 1인 Ubuntu 26.04 컨테이너를 만듭니다(`--privileged --cgroupns=host`). `run_test.sh`는 그 안에서 다음을 차례로 검증합니다.
1. 잘못된 버전 형식을 거부하는지, `7.4.15`를 고정 설치할 수 있는지, 버전을 생략하면 7.4 최신(7.4.16)으로 업그레이드되는지, `zabbix_get`이 설치되는지
2. 잘못된 Hostname·HostMetadata(허용되지 않은 문자, 2034자 초과)를 거부하는지, 4줄 입력(`Server`/`ServerActive`/`Hostname`/`HostMetadata`)이 `-f` 파일 입력(CRLF 포함)·대화형 입력·인자 입력으로 반영되는지, HostMetadata를 생략했을 때 입력 대기 없이 기존 값을 유지하는지
3. `/tmp`(다른 위치)에서 `3_deploy/deploy_agent2.sh <컨테이너 IP>`를 실행해 `/etc` 반영(HostMetadata 포함), enabled·active 상태, `agent.ping = 1`, `agent.hostname` 일치, 백업 파일 생성을 확인하는지
4. 6.1의 UserParameter(`custom.echo[*]`, JSON 반환)를 `zabbix_get`과 `zabbix_agent2 -t`로 조회할 수 있는지

테스트가 끝나거나 실패하면 trap이 컨테이너와 테스트 이미지를 **항상 삭제**합니다.

2026-11-06 실행 결과: Ubuntu 26.04.1 LTS에서 zabbix_agent2 7.4.16으로 모든 항목이 PASS였습니다.
