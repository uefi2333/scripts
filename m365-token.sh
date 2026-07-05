#!/bin/bash
# ================================================================
# M365 Copilot Refresh Token 获取工具
# 使用 Device Code Flow（设备码流）
# 兼容 Linux / macOS / Android Termux
# 无需账密输入，无需浏览器自动化
# ================================================================

set -e
RED='\e[0;31m'; GREEN='\e[0;32m'; YELLOW='\e[1;33m'; CYAN='\e[0;36m'; NC='\e[0m'

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   M365 Copilot Token 获取工具          ║${NC}"
echo -e "${CYAN}║   Device Code Flow · 无需密码           ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo

# 检查依赖
for cmd in curl python3; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${RED}错误: 缺少 $cmd${NC}"
        exit 1
    fi
done

# Microsoft 365 客户端 ID
# Teams Web: 1fec8e78-bce4-4aaf-ab1b-5451cc387264
# Office 365: d3590ed6-52b3-4102-aeff-aad2292ab01c
# Microsoft Graph: 无特定客户端，用通用入口
CLIENT_ID="4765445b-32c6-49b0-83e6-1d93765276ca"
SCOPE="https://substrate.office.com/sydney/.default openid profile offline_access"

echo -e "${YELLOW}[1/3] 正在请求设备码...${NC}"

# 请求设备码
DEVICE_REQ=$(curl -s -X POST "https://login.microsoftonline.com/common/oauth2/v2.0/devicecode" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=$CLIENT_ID&scope=$(echo $SCOPE | sed 's/ /%20/g')")

USER_CODE=$(echo "$DEVICE_REQ" | python3 -c "import sys,json; print(json.load(sys.stdin).get('user_code',''))")
DEVICE_CODE=$(echo "$DEVICE_REQ" | python3 -c "import sys,json; print(json.load(sys.stdin).get('device_code',''))")
VERIF_URI=$(echo "$DEVICE_REQ" | python3 -c "import sys,json; print(json.load(sys.stdin).get('verification_uri','https://microsoft.com/devicelogin'))")

if [ -z "$USER_CODE" ]; then
    echo -e "${RED}❌ 请求设备码失败${NC}"
    echo "响应: $DEVICE_REQ"
    exit 1
fi

echo
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          请完成以下步骤                  ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                          ║${NC}"
echo -e "${GREEN}║  1️⃣ 打开浏览器访问:${NC}"
echo -e "${YELLOW}║     ${VERIF_URI}${NC}"
echo -e "${GREEN}║                                          ║${NC}"
echo -e "${GREEN}║  2️⃣ 输入代码:${NC}"
echo -e "${YELLOW}║     ${USER_CODE}${NC}"
echo -e "${GREEN}║                                          ║${NC}"
echo -e "${GREEN}║  3️⃣ 登录你的 Microsoft 账号             ║${NC}"
echo -e "${GREEN}║                                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo

# 尝试自动打开浏览器
if command -v termux-open-url &>/dev/null; then
    termux-open-url "$VERIF_URI"
elif command -v xdg-open &>/dev/null; then
    xdg-open "$VERIF_URI" 2>/dev/null || true
elif command -v open &>/dev/null; then
    open "$VERIF_URI" 2>/dev/null || true
fi

echo -e "${YELLOW}[2/3] 等待验证完成...${NC}"
echo -e "（脚本会自动轮询，完成后自动继续）"
echo

# 轮询 token
INTERVAL=5
MAX_ATTEMPTS=60
ATTEMPT=0
SUCCESS=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    sleep $INTERVAL

    TOKEN_RESPONSE=$(curl -s -X POST "https://login.microsoftonline.com/common/oauth2/v2.0/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=$CLIENT_ID&device_code=$DEVICE_CODE")

    if echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0) if d.get('access_token') else sys.exit(1)" 2>/dev/null; then
        SUCCESS=1
        break
    fi

    ERROR=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error',''))" 2>/dev/null)
    
    if [ "$ERROR" = "authorization_pending" ]; then
        echo -ne "\r⏳ 等待授权中... 已等待 $((ATTEMPT * INTERVAL)) 秒"
    elif [ "$ERROR" = "slow_down" ]; then
        INTERVAL=$((INTERVAL + 5))
        echo -e "\n${YELLOW}⚠️  请求过于频繁，已降低轮询频率${NC}"
    else
        echo -ne "\r仍在等待..."
    fi
done

echo

if [ $SUCCESS -eq 0 ]; then
    echo -e "${RED}❌ 超时未完成验证${NC}"
    exit 1
fi

echo -e "${GREEN}[3/3] Token 获取成功！${NC}"
echo

# 提取关键信息
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))")
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))")
ID_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id_token',''))")
SCOPE_RET=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('scope',''))")
EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('expires_in',''))")

echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✅ Token 获取成功               ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  过期时间: ${EXPIRES_IN}s  (约 $((EXPIRES_IN/3600)) 小时)${NC}"
echo -e "${GREEN}║  权限范围: ${SCOPE_RET:0:50}...${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo
echo -e "${CYAN}── Access Token ──${NC}"
echo "${ACCESS_TOKEN:0:80}...${ACCESS_TOKEN: -20}"
echo
echo -e "${GREEN}── Refresh Token ──${NC}"
echo "${REFRESH_TOKEN:0:80}...${REFRESH_TOKEN: -20}"
echo
echo -e "${YELLOW}📌 Refresh Token 永不过期，除非吊销${NC}"
echo -e "${YELLOW}📌 用它换新 AT 的命令:${NC}"
echo
echo "curl -s -X POST https://login.microsoftonline.com/common/oauth2/v2.0/token \"
echo "  -H "Content-Type: application/x-www-form-urlencoded" \"
echo "  -d "client_id=$CLIENT_ID" \"
echo "  -d "grant_type=refresh_token" \"
echo "  -d "refresh_token=$REFRESH_TOKEN" | python3 -m json.tool"
echo

# 保存到文件
OUTPUT_DIR="$(pwd)"
if [ -d "/sdcard" ]; then
    OUTPUT_DIR="/sdcard"
fi
OUTPUT_FILE="${OUTPUT_DIR}/m365_tokens_$(date +%Y%m%d_%H%M%S).txt"

{
    echo "=== Microsoft 365 Tokens ==="
    echo "AccessToken: $ACCESS_TOKEN"
    echo "RefreshToken: $REFRESH_TOKEN"
    echo "IdToken: $ID_TOKEN"
    echo "Scope: $SCOPE_RET"
    echo "ExpiresIn: $EXPIRES_IN"
    echo "ObtainedAt: $(date -Iseconds 2>/dev/null || date)"
} > "$OUTPUT_FILE"

echo -e "${GREEN}✅ 已保存到: ${OUTPUT_FILE}${NC}"
echo
echo -e "${YELLOW}⚠️  此文件包含敏感令牌，等同密码！不要分享！${NC}"
