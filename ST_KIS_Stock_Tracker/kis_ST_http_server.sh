#!/bin/bash

# 설정
PYTHON_SCRIPT="kis_ST_http_server.py"
PID_FILE="kis_ST_http_server.pid"
LOG_FILE="kis_ST_http_server.log"
LOG_ROTATE_PID="kis_ST_http_server_rotate.pid"
MAX_LOG_SIZE=5242880  # 5MB (bytes)
KEEP_LOG_SIZE=2097152 # 초과 시 이만큼 남김 (2MB)

# 로그 로테이션 백그라운드 프로세스
rotate_log() {
    while true; do
        sleep 60  # 1분마다 확인
        if [ -f "$LOG_FILE" ]; then
            size=$(wc -c < "$LOG_FILE")
            if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
                tail -c "$KEEP_LOG_SIZE" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
                echo "[$(date '+%H:%M:%S')] ♻️ 로그 정리됨 (5MB 초과 → 최근 2MB 유지)" >> "$LOG_FILE"
            fi
        fi
    done
}

start() {
    if [ -f $PID_FILE ] && kill -0 $(cat $PID_FILE) 2>/dev/null; then
        echo "✅ 서버가 이미 실행 중입니다. (PID: $(cat $PID_FILE))"
    else
        echo "🚀 서버를 시작합니다 (자동 재시작 + 로그 로테이션 활성화)..."

        # 파이썬 서버 무한 재시작 루프
        nohup sh -c "until python3 $PYTHON_SCRIPT >> $LOG_FILE 2>&1; do
            echo \"[$(date '+%H:%M:%S')] ⚠️ 서버 종료됨. 5초 후 재시작...\" >> $LOG_FILE
            sleep 5
        done" > /dev/null 2>&1 &
        echo $! > $PID_FILE
        echo "✅ 서버 시작됨 (PID: $!)"

        # 로그 로테이션 백그라운드 시작
        rotate_log &
        echo $! > $LOG_ROTATE_PID
        echo "♻️ 로그 로테이션 시작됨 (PID: $!)"
    fi
}

stop() {
    if [ -f $PID_FILE ]; then
        PID=$(cat $PID_FILE)
        echo "🛑 서버를 종료합니다 (PID: $PID)..."
        pkill -P $PID > /dev/null 2>&1
        kill $PID > /dev/null 2>&1
        pgrep -f $PYTHON_SCRIPT | xargs kill > /dev/null 2>&1
        rm -f $PID_FILE
        echo "✅ 서버 종료 완료."
    else
        echo "❓ 실행 중인 서버가 없습니다."
    fi

    # 로그 로테이션도 종료
    if [ -f $LOG_ROTATE_PID ]; then
        kill $(cat $LOG_ROTATE_PID) > /dev/null 2>&1
        rm -f $LOG_ROTATE_PID
        echo "✅ 로그 로테이션 종료 완료."
    fi
}

status() {
    if [ -f $PID_FILE ] && kill -0 $(cat $PID_FILE) 2>/dev/null; then
        SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        SIZE_MB=$(echo "scale=2; $SIZE / 1048576" | bc)
        echo "🟢 서버 상태: 실행 중 (PID: $(cat $PID_FILE))"
        echo "📄 로그 크기: ${SIZE_MB}MB / 5MB"
        echo "--- 최근 로그 ---"
        tail -n 5 $LOG_FILE
    else
        echo "🔴 서버 상태: 중지됨"
    fi
}

case "$1" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    *) echo "사용법: $0 {start|stop|status}" ;;
esac
