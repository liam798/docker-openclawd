@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

REM 若没有 .env，从示例复制
if not exist .env (
  copy .env.example .env >nul
  echo [docker-setup] 已创建 .env（可从 .env.example 修改）
)

REM 若 .env 中 OPENCLAW_GATEWAY_TOKEN 为空，用 PowerShell 生成并写回
powershell -NoProfile -Command "$c = Get-Content .env -Raw -ErrorAction SilentlyContinue; if ($c -and $c -notmatch 'OPENCLAW_GATEWAY_TOKEN=.+') { $b = New-Object byte[] 24; (New-Object Security.Cryptography.RNGCryptoServiceProvider).GetBytes($b); $t = -join ($b | ForEach-Object { $_.ToString('x2') }); if ($c -match 'OPENCLAW_GATEWAY_TOKEN=') { $c = $c -replace 'OPENCLAW_GATEWAY_TOKEN=.*', \"OPENCLAW_GATEWAY_TOKEN=$t\" } else { $c = $c.TrimEnd() + \"`nOPENCLAW_GATEWAY_TOKEN=$t`n\" }; Set-Content .env $c -NoNewline; Write-Host '[docker-setup] 已生成 OPENCLAW_GATEWAY_TOKEN 并写入 .env' }"

REM 确保数据目录存在
if not exist "data\openclaw" mkdir "data\openclaw"
if not exist "data\workspace" mkdir "data\workspace"

REM 若 openclaw-src 不存在则自动克隆
if not exist "openclaw-src\.git" (
  echo [docker-setup] 正在克隆 openclaw/openclaw 到 openclaw-src/ ...
  git clone --depth 1 https://github.com/openclaw/openclaw.git openclaw-src
)

echo [docker-setup] 构建镜像（首次较慢）...
docker compose build
if errorlevel 1 exit /b 1

echo [docker-setup] 启动 Gateway...
docker compose up -d openclaw-gateway
if errorlevel 1 exit /b 1

REM 等待 Gateway 启动并自动安装飞书插件
echo [docker-setup] 等待 Gateway 就绪并安装飞书插件...
timeout /t 8 /nobreak >nul

REM 自动安装飞书插件（若未安装）
echo [docker-setup] 检查并安装飞书插件...
docker compose run --rm openclaw-cli plugins list 2>nul | findstr /i "feishu" >nul
if errorlevel 1 (
  echo [docker-setup] 正在安装飞书插件 @m1heng-clawd/feishu ...
  docker compose run --rm openclaw-cli plugins install @m1heng-clawd/feishu >nul 2>&1
  if errorlevel 1 (
    echo [docker-setup] 警告: 飞书插件安装失败，可稍后手动安装:
    echo   docker compose run --rm openclaw-cli plugins install @m1heng-clawd/feishu
  ) else (
    echo [docker-setup] 飞书插件安装成功
  )
) else (
  echo [docker-setup] 飞书插件已安装
)

echo.
echo Gateway 已启动。
echo   - Control UI: http://127.0.0.1:18789/
echo   - 若设置了 OPENCLAW_GATEWAY_TOKEN，请在 Control UI 设置中填入该令牌。
echo.
echo 首次使用建议执行: docker compose run --rm openclaw-cli onboard
echo 配置飞书通道: docker compose run --rm openclaw-cli config set channels.feishu.appId "YOUR_APP_ID"
echo 查看日志: docker compose logs -f openclaw-gateway
endlocal
