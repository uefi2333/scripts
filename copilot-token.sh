#!/bin/bash
# ================================================================
# M365 Copilot Refresh Token 获取工具 v3 - 调试版
# 显示每次轮询的完整响应，方便排查
# ================================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

CLIENT_ID="4765445b-32c6-49b0-83e6-1d93765276ca"
SCOPE_URL="https%3A%2F%2Fsubstrate.office.com%2Fsydney%2F.default%20openid%20profile%20offline_access"
TOKEN_URL="https://login.microsoftonline.com/common/oauth2/v2.0/token"
DEVICE_URL="https://login.microsoftonline.com/common/oauth2/v2.0/devicecode"

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   M365 Copilot Refresh Token v3         ║${NC}"
echo -e "${CYAN}║   调试版 · 显示轮询完整响应              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo

command -v curl &>/dev/null || { echo -e "${RED}缺少 curl${NC}"; exit 1; }
command -v python3 &>/dev/null || { echo -e "${RED}缺少 python3${NC}"; exit 1; }

# Step 1
echo -e "${YELLOW}[1/3] 获取设备码...${NC}"
DEVICE_RESP=$(curl -s --max-time 15 -X POST "$DEVICE_URL"     -H "Content-Type: application/x-www-form-urlencoded"     -d "client_id=$CLIENT_ID&scope=$SCOPE_URL")

USER_CODE=$(echo "$DEVICE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('user_code',''))" 2>/dev/null)
DEVICE_CODE=$(echo "$DEVICE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('device_code',''))" 2>/dev/null)

if [ -z "$USER_CODE" ]; then
    echo -e "${RED}❌ 失败:${NC}"
    echo "$DEVICE_RESP"
    exit 1
fi

echo -e "${GREEN}✅ 设备码: ${USER_CODE}${NC}"
echo
echo -e "打开 ${CYAN}https://microsoft.com/devicelogin${NC} 输入 ${YELLOW}${USER_CODE}${NC}"
echo

# 自动打开
command -v termux-open-url &>/dev/null && termux-open-url "https://microsoft.com/devicelogin" 2>/dev/null

# Step 2 - 调试轮询
echo -e "${YELLOW}[2/3] 开始轮询（每3秒一次，最长3分钟）${NC}"
echo -e "${YELLOW}登录完成后耐心等待脚本检测${NC}"
echo

for i in $(seq 1 60); do
    sleep 3
    
    # 尝试获取 token
    TOKEN_RESP=$(curl -s --max-time 10 -X POST "$TOKEN_URL"         -H "Content-Type: application/x-www-form-urlencoded"         -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=$CLIENT_ID&device_code=$DEVICE_CODE")
    
    # 完整响应保存到文件，方便调试
    echo "$TOKEN_RESP" > /tmp/copilot_debug_$i.json
    
    # 检查 access_token
    ACCESS_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('access_token',''))
except: print('PARSE_ERROR')" 2>/dev/null)
    
    if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "PARSE_ERROR" ]; then
        # 成功！
        REFRESH_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))" 2>/dev/null)
        
        echo -e "\n${GREEN}╔══════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║          ✅ Token 获取成功！              ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
        echo
        echo -e "${CYAN}═══ Access Token ═══${NC}"
        echo "$ACCESS_TOKEN"
        echo
        echo -e "${GREEN}═══ Refresh Token ═══${NC}"
        echo "$REFRESH_TOKEN"
        echo
        
        # 解码 JWT
        echo -e "${CYAN}═══ Token 信息 ═══${NC}"
        echo "$ACCESS_TOKEN" | python3 -c "
import sys,json,base64
at=sys.stdin.read().strip()
p=at.split('.')
if len(p)>=2:
    pad=4-len(p[1])%4
    if pad!=4: p[1]+='='*pad
    info=json.loads(base64.urlsafe_b64decode(p[1]))
    print(f'  client_id: $CLIENT_ID')
    print(f'  scope: https://substrate.office.com/sydney/.default')
    print(f'  aud: {info.get("aud","?")}')
    print(f'  appid: {info.get("appid","?")}')
    print(f'  scp: {info.get("scp","?")}')" 2>/dev/null
        echo
        
        # 保存
        OUTPUT_DIR="$(pwd)"; [ -d "/sdcard" ] && OUTPUT_DIR="/sdcard"
        OUTPUT_FILE="${OUTPUT_DIR}/copilot_tokens_$(date +%Y%m%d_%H%M%S).txt"
        echo "RefreshToken: $REFRESH_TOKEN" > "$OUTPUT_FILE"
        echo "AccessToken: $ACCESS_TOKEN" >> "$OUTPUT_FILE"
        echo -e "${GREEN}✅ 已保存: ${OUTPUT_FILE}${NC}"
        echo
        echo -e "${YELLOW}═══ 换新 AT 命令 ═══${NC}"
        echo "curl -s -X POST $TOKEN_URL \"
        echo "  -H "Content-Type: application/x-www-form-urlencoded" \"
        echo "  -d "client_id=$CLIENT_ID" \"
        echo "  -d "grant_type=refresh_token" \"
        echo "  -d "refresh_token=$REFRESH_TOKEN" | python3 -m json.tool"
        exit 0
    fi
    
    # 显示错误详情
    ERROR=$(echo "$TOKEN_RESP" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('error','?'), '|', d.get('error_description','')[:80])
except: print('JSON_PARSE_ERROR')" 2>/dev/null)
    
    printf "\r⏳ [%02d/60] %s" "$i" "$ERROR"
done

echo -e "\n${RED}❌ 超时${NC}"
echo
echo -e "${YELLOW}调试文件已保存到 /tmp/copilot_debug_*.json${NC}"
echo -e "${YELLOW}可以检查最后一个文件看看实际返回了什么: cat /tmp/copilot_debug_59.json${NC}"
