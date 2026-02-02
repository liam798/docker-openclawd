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

REM 读取 Gateway token（用于后续配置）
for /f "tokens=2 delims==" %%a in ('findstr /b "OPENCLAW_GATEWAY_TOKEN=" .env 2^>nul') do set GATEWAY_TOKEN=%%a
set GATEWAY_TOKEN=%GATEWAY_TOKEN:"=%

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
REM 注意：清空代理环境变量，避免容器内 127.0.0.1 无法访问宿主机代理
echo [docker-setup] 检查并安装飞书插件...
docker compose run --rm -e HTTP_PROXY= -e HTTPS_PROXY= -e http_proxy= -e https_proxy= -e ALL_PROXY= -e all_proxy= -e NO_PROXY=* -e no_proxy=* openclaw-cli plugins list 2>nul | findstr /i "feishu" >nul
if errorlevel 1 (
  echo [docker-setup] 正在安装飞书插件 @m1heng-clawd/feishu ...
  docker compose run --rm -e HTTP_PROXY= -e HTTPS_PROXY= -e http_proxy= -e https_proxy= -e ALL_PROXY= -e all_proxy= -e NO_PROXY=* -e no_proxy=* openclaw-cli plugins install @m1heng-clawd/feishu >nul 2>&1
  if errorlevel 1 (
    echo [docker-setup] 警告: 飞书插件安装失败，可稍后手动安装:
    echo   HTTP_PROXY= HTTPS_PROXY= docker compose run --rm openclaw-cli plugins install @m1heng-clawd/feishu
  ) else (
    echo [docker-setup] 飞书插件安装成功
  )
) else (
  echo [docker-setup] 飞书插件已安装
)

REM 自动执行 onboarding（若配置不存在）
if not exist "data\openclaw\openclaw.json" (
  echo [docker-setup] 检测到首次运行，执行自动配置（onboarding）...
  
  REM 等待 Gateway 完全就绪
  echo [docker-setup] 等待 Gateway 完全就绪...
  timeout /t 10 /nobreak >nul
  
  REM 创建最小配置文件（使用 gateway.auth.token 新格式）
  echo [docker-setup] 创建最小配置文件...
  if not exist "data\openclaw" mkdir "data\openclaw"
  (
    echo {
    echo   "gateway": {
    echo     "auth": {
    if defined GATEWAY_TOKEN (
      echo       "token": "%GATEWAY_TOKEN%"
    ) else (
      echo       "token": ""
    )
    echo     }
    echo   }
    echo }
  ) > "data\openclaw\openclaw.json"
  
  REM 如果有 token，通过 CLI 设置（使用新格式）
  if defined GATEWAY_TOKEN (
    echo [docker-setup] 设置 Gateway token...
    docker compose run --rm -e HTTP_PROXY= -e HTTPS_PROXY= -e http_proxy= -e https_proxy= -e ALL_PROXY= -e all_proxy= -e NO_PROXY=* -e no_proxy=* openclaw-cli config set gateway.auth.token "%GATEWAY_TOKEN%" >nul 2>&1
  )
  
  REM 尝试运行 onboard（可能需要交互）
  echo [docker-setup] 运行 onboarding 配置向导（可能需要交互）...
  echo [docker-setup] 提示: 如果出现交互提示，可按 Ctrl+C 跳过，稍后手动执行: docker compose run --rm openclaw-cli onboard
  timeout /t 30 docker compose run --rm openclaw-cli onboard >nul 2>&1
  if errorlevel 1 (
    echo [docker-setup] Onboarding 可能需要交互式输入，已跳过
    echo [docker-setup] Gateway 已使用最小配置启动，可通过 Control UI 或 CLI 完善配置
  )
) else (
  echo [docker-setup] 检测到已有配置文件，跳过 onboarding
  
  REM 自动迁移旧配置格式（gateway.token -> gateway.auth.token）
  echo [docker-setup] 检查并迁移旧配置格式...
  powershell -NoProfile -Command "$p = 'data\openclaw\openclaw.json'; if (Test-Path $p) { $data = Get-Content $p -Raw | ConvertFrom-Json; if ($data.gateway.token -and -not $data.gateway.auth.token) { $data.gateway.auth = @{token = $data.gateway.token}; $data.gateway.PSObject.Properties.Remove('token'); $data | ConvertTo-Json -Depth 10 | Set-Content $p -NoNewline; Write-Host '[docker-setup] 配置已迁移到 gateway.auth.token' } }" 2>nul
)

echo.
echo ✅ Gateway 已启动并配置完成！
echo   - Control UI: http://127.0.0.1:18789/
if defined GATEWAY_TOKEN (
  echo   - Gateway Token: %GATEWAY_TOKEN%
  echo   - 请在 Control UI 设置中填入该令牌
)
echo.
echo 后续配置：
echo   - 配置飞书通道: docker compose run --rm openclaw-cli config set channels.feishu.appId "YOUR_APP_ID"
echo   - 查看日志: docker compose logs -f openclaw-gateway
echo   - 完整配置向导: docker compose run --rm openclaw-cli onboard
endlocal
