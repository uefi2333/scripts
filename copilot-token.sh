#!/bin/bash
# ================================================================
# M365 Copilot Refresh Token 获取工具 v2
# Device Code Flow · 特供版
# 修复轮询逻辑，独立于 Termux / Linux / macOS
# ================================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# Copilot 参数（与 M365-Copilot2API 完全匹配）
CLIENT_ID="4765445b-32c6-49b0-83e6-1d93765276ca"
SCOPE="https://substrate.office.com/sydney/.default openid profile offline_access"
SCOPE_URL="https%3A%2F%2Fsubstrate.office.com%2Fsydney%2F.default%20openid%20profile%20offline_access"
TOKEN_URL="https://login.microsoftonline.com/common/oauth2/v2.0/token"
DEVICE_URL="https://login.microsoftonline.com/common/oauth2/v2.0/devicecode"

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   M365 Copilot Refresh Token 获取工具   ║${NC}"
echo -e "${CYAN}║   v2 · 修复轮询逻辑                     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo

# 检查依赖
for cmd in curl python3; do
    command -v $cmd &>/dev/null || { echo -e "${RED}缺少 $cmd${NC}"; exit 1; }
done

# Step 1: 获取设备码
echo -e "${YELLOW}[1/3] 请求设备码...${NC}"
DEVICE_RESP=$(curl -s --max-time 15 -X POST "$DEVICE_URL"     -H "Content-Type: application/x-www-form-urlencoded"     -d "client_id=$CLIENT_ID&scope=$SCOPE_URL")

# 解析
USER_CODE=$(echo "$DEVICE_RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('user_code',''))")
DEVICE_CODE=$(echo "$DEVICE_RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('device_code',''))")

if [ -z "$USER_CODE" ]; then
    echo -e "${RED}❌ 设备码获取失败${NC}"
    echo "$DEVICE_RESP"
    exit 1
fi

echo -e "${GREEN}✅ 设备码已获取${NC}"
echo
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  1. 打开浏览器:${NC}"
echo -e "${YELLOW}║     https://microsoft.com/devicelogin${NC}"
echo -e "${GREEN}║                                          ║${NC}"
echo -e "${GREEN}║  2. 输入代码:${NC}"
echo -e "${YELLOW}║     ${USER_CODE}${NC}"
echo -e "${GREEN}║                                          ║${NC}"
echo -e "${GREEN}║  3. 登录你的微软账号${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo

# 自动打开浏览器
command -v termux-open-url &>/dev/null && termux-open-url "https://microsoft.com/devicelogin"
command -v xdg-open &>/dev/null && xdg-open "https://microsoft.com/devicelogin" 2>/dev/null || true

# Step 2: 轮询
echo -e "${YELLOW}[2/3] 等待授权（每3秒轮询一次，最长3分钟）...${NC}"
echo

TOKEN_RESPONSE=""
SUCCESS=0
for i in $(seq 1 60); do
    sleep 3
    
    # 静默请求
    TOKEN_RESPONSE=$(curl -s --max-time 10 -X POST "$TOKEN_URL"         -H "Content-Type: application/x-www-form-urlencoded"         -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=$CLIENT_ID&device_code=$DEVICE_CODE")
    
    # 检查是否拿到 access_token
    if echo "$TOKEN_RESPONSE" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if d.get('access_token'): sys.exit(0)
sys.exit(1)" 2>/dev/null; then
        SUCCESS=1
        break
    fi
    
    # 显示错误类型
    ERROR=$(echo "$TOKEN_RESPONSE" | python3 -c "
import sys,json
print(json.load(sys.stdin).get('error','?'))" 2>/dev/null)
    
    printf "\r⏳ 第 %2d/60 次轮询  [%s]" "$i" "$ERROR"
done

echo

if [ $SUCCESS -eq 0 ]; then
    echo -e "\n${RED}❌ 超时未获取到 token${NC}"
    echo -e "${YELLOW}提示: 确认是否在 https://microsoft.com/devicelogin 输入了代码 ${USER_CODE} 并完成授权${NC}"
    exit 1
fi

echo -e "\n${GREEN}[3/3] ✅ Token 获取成功！${NC}"
echo

# 解析
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))")
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))")

# 解码 JWT 显示信息
echo "$TOKEN_RESPONSE" | python3 -c "
import sys,json,base64
d=json.load(sys.stdin)
at=d.get('access_token','')
rt=d.get('refresh_token','')
print('═══ Token 信息 ═══')
print(f'  client_id: 4765445b-32c6-49b0-83e6-1d93765276ca')
print(f'  scope: https://substrate.office.com/sydney/.default')
if at:
    p=at.split('.')
    if len(p)>=2:
        pad=4-len(p[1])%4
        if pad!=4: p[1]+='='*pad
        info=json.loads(base64.urlsafe_b64decode(p[1]))
        print(f'  aud (目标资源): {info.get("aud","?")}')
        print(f'  appid: {info.get("appid","?")}')
        print(f'  scp: {info.get("scp","?")}')
print()
print('═══ Access Token ═══')
print(at)
print()
print('═══ Refresh Token ═══')
print(rt)
print()
print('═══ 换新 AT 命令（保存此命令） ═══')
print(f'curl -s -X POST https://login.microsoftonline.com/common/oauth2/v2.0/token \\')
print(f'  -H "Content-Type: application/x-www-form-urlencoded" \\')
print(f'  -d "client_id=4765445b-32c6-49b0-83e6-1d93765276ca" \\')
print(f'  -d "grant_type=refresh_token" \\')
print(f'  -d "refresh_token={rt}" | python3 -m json.tool')
" 2>/dev/null

# 保存到文件
OUTPUT_DIR="$(pwd)"
[ -d "/sdcard" ] && OUTPUT_DIR="/sdcard"
OUTPUT_FILE="${OUTPUT_DIR}/copilot_tokens_$(date +%Y%m%d_%H%M%S).txt"

{
    echo "=== M365 Copilot Tokens ==="
    echo "ClientID: 4765445b-32c6-49b0-83e6-1d93765276ca"
    echo "Scope: https://substrate.office.com/sydney/.default"
    echo "AccessToken: $ACCESS_TOKEN"
    echo "RefreshToken: $REFRESH_TOKEN"
    echo "ObtainedAt: $(date -Iseconds 2>/dev/null || date)"
} > "$OUTPUT_FILE"

echo -e "${GREEN}✅ 已保存到: ${OUTPUT_FILE}${NC}"
echo -e "${YELLOW}⚠️  敏感信息，不要分享！${NC}"
