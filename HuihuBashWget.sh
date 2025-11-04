#!/bin/sh

# ===== 基本配置 =====
readonly CONNECTIVITY_URL="http://connectivitycheck.gstatic.com/generate_204"
readonly PING_HOST="1.1.1.1"

readonly HUIHU_PWD="your pwd"
readonly HUIHU_ACC="your account, usually phone number"
readonly HUIHU_TELECOM="your service provider, e.g. telecom, cmcc, unicom"

readonly HUIHU_CHECK_INTERVAL_S=15
readonly CONNECT_TIMEOUT_S=5
readonly AUTH_TIMEOUT_S=8
DEBUG=1

PORTAL_URL="http://10.10.16.12/api/portal/v1/login"

HAVE_UC="$(command -v uclient-fetch 2>/dev/null || true)"
HAVE_WG="$(command -v wget 2>/dev/null || true)"
HAVE_PING="$(command -v ping 2>/dev/null || true)"

log() {
    msg="$1"
    now="$(date +'%H:%M:%S')"
    echo "$now: $msg"
    command -v logger >/dev/null 2>&1 && logger -t huihu-net -- "$msg"
}
dbg() { [ "$DEBUG" = "1" ] && log "[DBG] $*"; }

need_tools() {
    if [ -z "$HAVE_UC" ] && [ -z "$HAVE_WG" ]; then
        echo "FATAL: 未找到 uclient-fetch 或 wget。请执行: opkg update && opkg install uclient-fetch" >&2
        exit 127
    fi
    if [ -z "$HAVE_PING" ]; then
        echo "WARN: ping 不可用，将仅用 HTTP 探测。建议: opkg install iputils-ping 或 busybox-full" >&2
    fi
}

# 通用 HTTP POST（优先 uclient-fetch）
http_post() {
    url="$1"
    data="$2"

    if [ -n "$HAVE_UC" ]; then
        # uclient-fetch：OpenWrt 原生，支持 --post-data/--header
        out="$(
            uclient-fetch -q -T "$AUTH_TIMEOUT_S" -O - \
                --header 'Content-Type: application/json; charset=UTF-8' \
                --post-data "$data" \
                "$url" 2>/dev/null
        )"
        rc=$?
        printf "%s" "$out"
        return $rc
    elif [ -n "$HAVE_WG" ]; then
        # BusyBox wget 回退：不使用 --server-response，避免不支持的选项
        out="$(
            wget -q -T "$AUTH_TIMEOUT_S" -O - \
                --header='Content-Type: application/json; charset=UTF-8' \
                --post-data="$data" \
                "$url" 2>/dev/null
        )"
        rc=$?
        printf "%s" "$out"
        return $rc
    else
        return 127
    fi
}

check_connectivity() {
    # 先 ping，一包一秒内
    if [ -n "$HAVE_PING" ]; then
        if ping -c 1 -W "$CONNECT_TIMEOUT_S" -w "$CONNECT_TIMEOUT_S" "$PING_HOST" >/dev/null 2>&1; then
            dbg "ping $PING_HOST OK"
            return 0
        fi
        dbg "ping $PING_HOST FAIL"
    fi
    # 再尝试 HTTP 204 探测
    if [ -n "$HAVE_UC" ]; then
        if uclient-fetch -q -T "$CONNECT_TIMEOUT_S" --spider "$CONNECTIVITY_URL" >/dev/null 2>&1; then
            dbg "uclient-fetch --spider $CONNECTIVITY_URL OK"
            return 0
        fi
        dbg "uclient-fetch --spider $CONNECTIVITY_URL FAIL"
    elif [ -n "$HAVE_WG" ]; then
        if wget -q -T "$CONNECT_TIMEOUT_S" --spider "$CONNECTIVITY_URL" >/dev/null 2>&1; then
            dbg "wget --spider $CONNECTIVITY_URL OK"
            return 0
        fi
        dbg "wget --spider $CONNECTIVITY_URL FAIL"
    fi
    return 1
}

huihu_auth() {
    payload=$(printf '{"domain":"%s","username":"%s","password":"%s"}' \
        "$HUIHU_TELECOM" "$HUIHU_ACC" "$HUIHU_PWD")

    body="$(http_post "$PORTAL_URL" "$payload")"
    rc=$?

    if [ $rc -ne 0 ]; then
        log "huihu_auth: HTTP 客户端失败（rc=$rc）"
        [ "$DEBUG" = "1" ] && echo "STDOUT(可能为空): $body"
        return 3
    fi

    # 打印返回体（便于调试/观察门户返回）
    [ "$DEBUG" = "1" ] && echo "Response body: $body"

    # 常见成功关键字（按需增改）
    echo "$body" | grep -Eiq '"code"\s*:\s*0|success|ok' && {
        log "huihu_auth: 服务器返回成功标志"
        return 0
    }

    # 不确定就乐观重试：让后续连通性探测来判定是否生效
    log "huihu_auth: 已发送认证请求（未识别到明确成功码）"
    return 0
}

trap 'echo; log "收到中断信号，退出。"; exit 0' INT TERM

need_tools

while true; do
    if check_connectivity; then
        log "connectivity OK；$HUIHU_CHECK_INTERVAL_S 秒后复查"
        sleep "$HUIHU_CHECK_INTERVAL_S"
        continue
    fi

    log "连通性失败；尝试进行 Huihu 认证……"
    if huihu_auth; then
        log "认证请求已发出；稍后复查连通性"
    else
        rc=$?
        case "$rc" in
        3) log "网络/套接字错误，稍后重试。" ;;
        *) log "认证错误，稍后重试。" ;;
        esac
    fi
    sleep "$HUIHU_CHECK_INTERVAL_S"
done
