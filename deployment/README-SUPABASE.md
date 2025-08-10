# Synapse Matrix 服务器 Supabase 部署指南

本指南详细介绍如何使用 Docker 在 Supabase 上部署带有好友管理功能的 Synapse Matrix 服务器。

## 📋 目录

- [系统要求](#系统要求)
- [Supabase 准备](#supabase-准备)
- [快速部署](#快速部署)
- [手动部署](#手动部署)
- [配置说明](#配置说明)
- [服务管理](#服务管理)
- [好友功能测试](#好友功能测试)
- [监控和日志](#监控和日志)
- [故障排除](#故障排除)
- [安全建议](#安全建议)
- [备份和恢复](#备份和恢复)

## 🔧 系统要求

### 服务器要求
- **操作系统**: Ubuntu 20.04+ / CentOS 8+ / Debian 11+
- **内存**: 最少 2GB，推荐 4GB+
- **存储**: 最少 20GB 可用空间
- **网络**: 公网 IP 地址
- **域名**: 已配置 DNS 解析的域名

### 软件要求
- Docker 20.10+
- Docker Compose 2.0+
- curl
- openssl

### 端口要求
- `8008`: HTTP 客户端 API
- `8448`: HTTPS 联邦 API
- `8080`: Element Web 客户端 (可选)
- `3000`: Grafana 监控 (可选)
- `9090`: Prometheus 监控 (可选)

## 🗄️ Supabase 准备

### 1. 创建 Supabase 项目

1. 访问 [Supabase](https://supabase.com) 并登录
2. 点击 "New Project" 创建新项目
3. 选择组织和区域（推荐选择离用户最近的区域）
4. 设置项目名称和数据库密码
5. 等待项目创建完成

### 2. 获取数据库连接信息

1. 进入项目仪表板
2. 点击左侧菜单 "Settings" -> "Database"
3. 在 "Connection info" 部分找到以下信息：
   - **Host**: `db.xxx.supabase.co`
   - **Database name**: `postgres`
   - **Port**: `5432`
   - **User**: `postgres`
   - **Password**: 你设置的密码

### 3. 配置数据库访问

1. 在 "Settings" -> "Database" -> "Connection pooling" 中
2. 确保启用了 "Connection pooling"
3. 记录连接池的端口（通常是 6543）

## 🚀 快速部署

### 使用自动化脚本

```bash
# 克隆项目
git clone <your-synapse-repo>
cd synapse/deployment

# 给脚本执行权限
chmod +x deploy-supabase.sh

# 运行部署脚本
./deploy-supabase.sh
```

脚本会引导你完成以下步骤：
1. 输入域名
2. 输入 Supabase 数据库信息
3. 选择可选功能（Redis、Element Web、监控等）
4. 自动生成安全密钥
5. 构建和启动服务
6. 创建管理员用户

## 🔧 手动部署

### 1. 准备环境

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装 Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# 安装 Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 重新登录以应用 Docker 组权限
newgrp docker
```

### 2. 配置环境变量

```bash
# 复制环境变量模板
cp .env.supabase.example .env

# 编辑配置文件
nano .env
```

必须配置的变量：
```bash
# 基本配置
SYNAPSE_SERVER_NAME=matrix.yourdomain.com

# Supabase 数据库
SUPABASE_DB_HOST=db.xxx.supabase.co
SUPABASE_DB_PASSWORD=your_supabase_password

# 安全密钥（使用 openssl rand -hex 32 生成）
REGISTRATION_SHARED_SECRET=your_registration_secret
MACARRON_SECRET_KEY=your_macaroon_secret
FORM_SECRET=your_form_secret
```

### 3. 创建必要目录

```bash
mkdir -p data logs ssl
chmod 755 data logs ssl
```

### 4. 构建和启动服务

```bash
# 构建 Docker 镜像
docker build -f Dockerfile.supabase -t synapse-supabase:latest ..

# 启动基础服务
docker-compose -f docker-compose.supabase.yml up -d

# 启动可选服务（Element Web）
docker-compose -f docker-compose.supabase.yml --profile element up -d

# 启动监控服务
docker-compose -f docker-compose.supabase.yml --profile monitoring up -d
```

### 5. 验证部署

```bash
# 检查服务状态
docker-compose -f docker-compose.supabase.yml ps

# 检查健康状态
curl http://localhost:8008/health

# 查看日志
docker-compose -f docker-compose.supabase.yml logs -f synapse
```

### 6. 创建管理员用户

```bash
docker-compose -f docker-compose.supabase.yml exec synapse \
    register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008
```

## ⚙️ 配置说明

### 核心配置文件

| 文件 | 描述 |
|------|------|
| `Dockerfile.supabase` | Supabase 专用 Docker 镜像 |
| `docker-compose.supabase.yml` | Docker Compose 配置 |
| `supabase-homeserver.yaml` | Synapse 服务器配置模板 |
| `supabase-log.config` | 日志配置 |
| `supabase-start.sh` | 容器启动脚本 |
| `.env.supabase.example` | 环境变量模板 |

### 好友功能配置

在 `supabase-homeserver.yaml` 中的好友功能配置：

```yaml
friends:
  enabled: true
  max_friends_per_user: 1000
  friend_request_timeout: 604800  # 7 days
  allow_cross_domain_friends: true
  friend_request_rate_limit:
    per_second: 0.1
    burst_count: 5
```

### 数据库配置

Supabase PostgreSQL 配置：

```yaml
database:
  name: psycopg2
  args:
    user: postgres
    password: ${SUPABASE_DB_PASSWORD}
    database: postgres
    host: ${SUPABASE_DB_HOST}
    port: 5432
    sslmode: require
    cp_min: 5
    cp_max: 20
```

## 🔄 服务管理

### 基本命令

```bash
# 查看服务状态
docker-compose -f docker-compose.supabase.yml ps

# 启动服务
docker-compose -f docker-compose.supabase.yml up -d

# 停止服务
docker-compose -f docker-compose.supabase.yml down

# 重启服务
docker-compose -f docker-compose.supabase.yml restart

# 查看日志
docker-compose -f docker-compose.supabase.yml logs -f

# 查看特定服务日志
docker-compose -f docker-compose.supabase.yml logs -f synapse
```

### 更新服务

```bash
# 拉取最新镜像
docker-compose -f docker-compose.supabase.yml pull

# 重新构建自定义镜像
docker build -f Dockerfile.supabase -t synapse-supabase:latest ..

# 重启服务
docker-compose -f docker-compose.supabase.yml up -d
```

### 扩展服务

```bash
# 启动 Element Web 客户端
docker-compose -f docker-compose.supabase.yml --profile element up -d

# 启动监控服务
docker-compose -f docker-compose.supabase.yml --profile monitoring up -d

# 启动 Coturn TURN 服务器
docker-compose -f docker-compose.supabase.yml --profile coturn up -d
```

## 🤝 好友功能测试

### 1. 获取访问令牌

```bash
curl -X POST https://your-domain.com/_matrix/client/r0/login \
  -H "Content-Type: application/json" \
  -d '{
    "type": "m.login.password",
    "user": "@username:your-domain.com",
    "password": "password"
  }'
```

### 2. 发送好友请求

```bash
curl -X POST https://your-domain.com/_matrix/client/v1/friends/request \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "@friend:your-domain.com",
    "message": "Hello, let's be friends!"
  }'
```

### 3. 获取好友列表

```bash
curl -X GET https://your-domain.com/_matrix/client/v1/friends \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### 4. 接受好友请求

```bash
curl -X PUT https://your-domain.com/_matrix/client/v1/friends/request/REQUEST_ID \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "accepted"
  }'
```

### 5. 删除好友

```bash
curl -X DELETE https://your-domain.com/_matrix/client/v1/friends/@friend:your-domain.com \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

## 📊 监控和日志

### 日志文件位置

- **Synapse 主日志**: `logs/homeserver.log`
- **错误日志**: `logs/error.log`
- **好友功能日志**: `logs/friends.log`

### 监控服务

如果启用了监控服务：

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000 (admin/密码在 .env 文件中)

### 健康检查

```bash
# 检查 Synapse 健康状态
curl http://localhost:8008/health

# 检查 Matrix 版本
curl http://localhost:8008/_matrix/client/versions

# 检查联邦状态
curl http://localhost:8008/_matrix/federation/v1/version
```

## 🔧 故障排除

### 常见问题

#### 1. 数据库连接失败

**症状**: 容器启动失败，日志显示数据库连接错误

**解决方案**:
```bash
# 检查 Supabase 连接信息
psql "postgresql://postgres:PASSWORD@HOST:5432/postgres?sslmode=require"

# 检查环境变量
docker-compose -f docker-compose.supabase.yml config

# 检查网络连接
telnet db.xxx.supabase.co 5432
```

#### 2. 服务启动超时

**症状**: 健康检查失败，服务无法访问

**解决方案**:
```bash
# 查看详细日志
docker-compose -f docker-compose.supabase.yml logs synapse

# 检查端口占用
sudo netstat -tlnp | grep :8008

# 重启服务
docker-compose -f docker-compose.supabase.yml restart synapse
```

#### 3. SSL/TLS 证书问题

**症状**: HTTPS 访问失败，证书错误

**解决方案**:
```bash
# 检查证书文件
ls -la ssl/

# 验证证书
openssl x509 -in ssl/fullchain.pem -text -noout

# 更新证书
sudo certbot renew
```

#### 4. 好友功能不工作

**症状**: 好友 API 返回 404 或 500 错误

**解决方案**:
```bash
# 检查好友功能日志
tail -f logs/friends.log

# 验证数据库表
psql "postgresql://postgres:PASSWORD@HOST:5432/postgres?sslmode=require" \
  -c "\dt *friends*"

# 重新运行数据库迁移
docker-compose -f docker-compose.supabase.yml exec synapse \
  python -m synapse.app.homeserver --config-path /data/homeserver.yaml --run-migrations
```

### 调试模式

启用调试模式：

```bash
# 在 .env 文件中设置
DEBUG=true
LOG_LEVEL=DEBUG

# 重启服务
docker-compose -f docker-compose.supabase.yml restart synapse
```

### 性能优化

#### 1. 数据库优化

```sql
-- 在 Supabase SQL 编辑器中执行
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
SELECT pg_reload_conf();
```

#### 2. 缓存优化

在 `.env` 文件中调整：

```bash
# 增加缓存因子
CACHE_FACTOR=1.0

# 启用 Redis
REDIS_ENABLED=true
```

## 🔒 安全建议

### 1. 网络安全

```bash
# 配置防火墙
sudo ufw enable
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 8448/tcp    # Matrix Federation
```

### 2. 密钥管理

- 使用强随机密钥：`openssl rand -hex 32`
- 定期轮换密钥
- 安全存储密钥文件
- 不要在日志中记录敏感信息

### 3. 访问控制

```yaml
# 在 homeserver.yaml 中配置
enable_registration: false
registration_shared_secret: "your_secret"
allow_guest_access: false
```

### 4. SSL/TLS 配置

```bash
# 使用 Let's Encrypt 获取免费证书
sudo certbot certonly --standalone -d your-domain.com

# 设置自动续期
sudo crontab -e
# 添加: 0 12 * * * /usr/bin/certbot renew --quiet
```

## 💾 备份和恢复

### 数据备份

```bash
# 备份 Supabase 数据库
pg_dump "postgresql://postgres:PASSWORD@HOST:5432/postgres?sslmode=require" \
  > synapse_backup_$(date +%Y%m%d).sql

# 备份媒体文件
tar -czf media_backup_$(date +%Y%m%d).tar.gz data/media_store/

# 备份配置文件
tar -czf config_backup_$(date +%Y%m%d).tar.gz .env *.yaml *.json
```

### 数据恢复

```bash
# 恢复数据库
psql "postgresql://postgres:PASSWORD@HOST:5432/postgres?sslmode=require" \
  < synapse_backup_20231201.sql

# 恢复媒体文件
tar -xzf media_backup_20231201.tar.gz

# 重启服务
docker-compose -f docker-compose.supabase.yml restart
```

### 自动备份脚本

```bash
#!/bin/bash
# backup.sh

BACKUP_DIR="/opt/synapse/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# 备份数据库
pg_dump "postgresql://postgres:$SUPABASE_DB_PASSWORD@$SUPABASE_DB_HOST:5432/postgres?sslmode=require" \
  > $BACKUP_DIR/synapse_db_$DATE.sql

# 备份媒体文件
tar -czf $BACKUP_DIR/synapse_media_$DATE.tar.gz data/media_store/

# 清理旧备份（保留 7 天）
find $BACKUP_DIR -name "synapse_*" -mtime +7 -delete

echo "备份完成: $DATE"
```

设置定时备份：

```bash
# 添加到 crontab
crontab -e
# 每天凌晨 2 点备份
0 2 * * * /opt/synapse/backup.sh
```

## 📚 参考资料

- [Synapse 官方文档](https://matrix-org.github.io/synapse/)
- [Matrix 规范](https://spec.matrix.org/)
- [Supabase 文档](https://supabase.com/docs)
- [Docker Compose 文档](https://docs.docker.com/compose/)
- [Element 客户端](https://element.io/)

## 🆘 获取帮助

如果遇到问题，可以：

1. 查看日志文件获取详细错误信息
2. 检查 [Synapse 官方文档](https://matrix-org.github.io/synapse/)
3. 访问 [Matrix 社区](https://matrix.to/#/#synapse:matrix.org)
4. 提交 Issue 到项目仓库

---

**注意**: 请将所有示例中的 `your-domain.com` 替换为你的实际域名，将密码替换为安全的随机密码。