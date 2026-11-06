# systemctl 을 쓰는 스크립트를 검증하기 위해 systemd 를 PID 1 로 띄우는 Ubuntu 26.04
FROM ubuntu:26.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends systemd systemd-sysv \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
