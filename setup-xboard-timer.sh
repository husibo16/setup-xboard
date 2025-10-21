#!/bin/bash
# ===============================================================
# 一键安装 Xboard + MariaDB 自动重启 systemd 定时任务
# 作者: 胡博涵
# 说明: 适用于 Debian / Ubuntu 系统
# ===============================================================

set -e

SERVICE_PATH="/etc/systemd/system/xboard-restart.service"
TIMER_PATH="/etc/systemd/system/xboard-restart.timer"
SCRIPT_PATH="/usr/local/bin/xboard-restart"
LOG_FILE="/var/log/xboard-restart.log"

echo "=== 🧩 开始安装 Xboard 自动重启定时任务 ==="

# 1️⃣ 创建主重启脚本
cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash
# ------------------------------------------------------------------
# Xboard + MariaDB 一键安全重启脚本（由定时任务自动调用）
# ------------------------------------------------------------------

LOG_FILE="/var/log/xboard-restart.log"

# 日志函数
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# 日志归档（>20MB 自动备份）
if [ -f "$LOG_FILE" ] && [ "$(du -m "$LOG_FILE" | cut -f1)" -gt 20 ]; then
  mv "$LOG_FILE" "${LOG_FILE}.$(date +%F-%H%M%S).bak"
fi

log "=== 开始执行 Xboard + MariaDB 一键重启 ==="

# 检查 Docker 服务
if ! systemctl is-active --quiet docker; then
  log "[WARN] Docker 未运行，尝试启动..."
  systemctl start docker
  sleep 3
fi
if ! docker info >/dev/null 2>&1; then
  log "[WARN] Docker 守护进程未响应，尝试重启..."
  systemctl restart docker
  sleep 5
fi

# 重启 Xboard 容器
log "正在重启 Xboard 容器..."
CONTAINERS=(xboard-web-1 xboard-horizon-1 xboard-redis-1)

for container in "${CONTAINERS[@]}"; do
  if docker ps --format '{{.Names}}' | grep -q "^$container$"; then
    log "→ 重启容器 $container"
    docker restart "$container" >/dev/null 2>&1 && \
      log "✅ $container 重启完成" || log "❌ $container 重启失败"
  else
    log "→ 容器 $container 不存在，跳过"
  fi
done

# 重启系统 MariaDB
if systemctl list-units --type=service | grep -q 'mariadb'; then
  log "检测到系统 MariaDB 服务，正在重启..."
  systemctl restart mariadb && log "✅ MariaDB 重启完成"
else
  log "⚠️ 未检测到系统 MariaDB 服务，跳过数据库重启。"
fi

# 清理 Docker 资源
log "清理无用 Docker 资源..."
docker system prune -f >/dev/null 2>&1

# 输出状态
log "当前运行中的容器："
docker ps --format "table {{.Names}}\t{{.Status}}" | tee -a "$LOG_FILE"

log "✅ 全部重启完成。日志已保存至：$LOG_FILE"
exit 0
EOF

chmod +x "$SCRIPT_PATH"

# 2️⃣ 创建 systemd 服务单元
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Xboard + MariaDB Daily Restart
After=docker.service mariadb.service

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
EOF

# 3️⃣ 创建 systemd 定时器（每天凌晨 3 点执行）
cat > "$TIMER_PATH" <<EOF
[Unit]
Description=Run xboard-restart daily at 3:00

[Timer]
OnCalendar=03:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 4️⃣ 启用定时器
systemctl daemon-reload
systemctl enable --now xboard-restart.timer

# 5️⃣ 验证结果
echo
echo "=== ✅ 安装完成，当前定时任务状态如下 ==="
systemctl list-timers --all | grep xboard-restart || true

echo
echo "日志路径: $LOG_FILE"
echo "可手动执行命令: xboard-restart"
echo "查看定时器状态: systemctl status xboard-restart.timer"
echo "查看执行日志: journalctl -u xboard-restart.service -n 20"
echo "==============================================="
