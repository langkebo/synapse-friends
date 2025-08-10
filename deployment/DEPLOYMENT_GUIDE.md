# Synapse Matrix 服务器 Ubuntu 部署指南

本指南详细介绍如何在 Ubuntu 服务器上部署带有好友管理功能的 Synapse Matrix 服务器。

## 系统要求

- Ubuntu 20.04 LTS 或更高版本
- 至少 2GB RAM（推荐 4GB+）
- 至少 20GB 存储空间
- 公网 IP 地址
- 域名（用于 SSL 证书）

## 部署方式选择

本指南提供两种部署方式：
1. **Docker 部署**（推荐）- 简单快速，易于管理
2. **原生部署** - 更好的性能，更灵活的配置

---

## 方式一：Docker 部署

### 1. 系统准备

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装必要软件
sudo apt install -y curl wget git ufw

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

### 2. 配置防火墙

```bash
# 启用 UFW
sudo ufw enable

# 允许必要端口
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 8448/tcp    # Matrix Federation
sudo ufw allow 3478/udp    # TURN server (可选)
sudo ufw allow 5349/tcp    # TURN server (可选)
```

### 3. 部署 Synapse

```bash
# 创建部署目录
mkdir -p /opt/synapse
cd /opt/synapse

# 复制 docker-compose.yml 文件
# 将提供的 docker-compose.yml 文件复制到此目录

# 创建必要目录
mkdir -p data config logs ssl

# 生成 Synapse 配置
docker run -it --rm \
    -v "$PWD/data:/data" \
    -e SYNAPSE_SERVER_NAME=your-domain.com \
    -e SYNAPSE_REPORT_STATS=no \
    matrixdotorg/synapse:latest generate

# 编辑配置文件
sudo nano data/homeserver.yaml
```

### 4. 配置 SSL 证书

```bash
# 安装 Certbot
sudo apt install -y certbot

# 获取 SSL 证书
sudo certbot certonly --standalone -d your-domain.com

# 复制证书到 Docker 目录
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem ssl/
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem ssl/
sudo chown -R 1000:1000 ssl/
```

### 5. 启动服务

```bash
# 启动所有服务
docker-compose up -d

# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f synapse
```

### 6. 创建管理员用户

```bash
# 进入 Synapse 容器
docker-compose exec synapse bash

# 创建管理员用户
register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008
```

---

## 方式二：原生部署

### 1. 系统准备

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装依赖
sudo apt install -y \
    python3 python3-pip python3-venv \
    postgresql postgresql-contrib \
    nginx certbot python3-certbot-nginx \
    redis-server \
    build-essential libffi-dev \
    python3-dev libssl-dev \
    libjpeg-dev libxslt1-dev \
    libpq-dev git
```

### 2. 配置 PostgreSQL

```bash
# 切换到 postgres 用户
sudo -u postgres psql

# 在 PostgreSQL 中执行
CREATE USER synapse WITH PASSWORD 'your_secure_password';
CREATE DATABASE synapse
    ENCODING 'UTF8'
    LC_COLLATE='C'
    LC_CTYPE='C'
    template=template0
    OWNER synapse;
\q

# 配置 PostgreSQL
sudo nano /etc/postgresql/*/main/pg_hba.conf
# 添加行：local synapse synapse md5

sudo systemctl restart postgresql
```

### 3. 安装 Synapse

```bash
# 创建 synapse 用户
sudo adduser --system --group --home /opt/synapse synapse

# 切换到 synapse 用户
sudo -u synapse -s
cd /opt/synapse

# 创建虚拟环境
python3 -m venv venv
source venv/bin/activate

# 安装 Synapse
pip install --upgrade pip setuptools
pip install matrix-synapse[postgres,redis]

# 生成配置文件
python -m synapse.app.homeserver \
    --server-name your-domain.com \
    --config-path /etc/synapse/homeserver.yaml \
    --generate-config \
    --report-stats=no
```

### 4. 配置 Synapse

```bash
# 编辑配置文件
sudo nano /etc/synapse/homeserver.yaml
```

关键配置项：

```yaml
# 数据库配置
database:
  name: psycopg2
  args:
    user: synapse
    password: your_secure_password
    database: synapse
    host: localhost
    cp_min: 5
    cp_max: 10

# Redis 配置
redis:
  enabled: true
  host: localhost
  port: 6379
  password: your_redis_password

# 监听配置
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['127.0.0.1']
    resources:
      - names: [client, federation]
        compress: false

# 媒体存储
media_store_path: "/var/lib/synapse/media"
max_upload_size: 50M

# 注册配置
enable_registration: false
registration_shared_secret: "your_registration_secret"

# 好友功能配置（新增）
friends:
  enabled: true
  max_friends_per_user: 1000
  friend_request_timeout: 604800  # 7 days
```

### 5. 配置 systemd 服务

```bash
# 复制服务文件
sudo cp deployment/synapse.service /etc/systemd/system/

# 创建必要目录
sudo mkdir -p /var/lib/synapse /var/log/synapse
sudo chown synapse:synapse /var/lib/synapse /var/log/synapse

# 启用并启动服务
sudo systemctl daemon-reload
sudo systemctl enable synapse
sudo systemctl start synapse

# 检查状态
sudo systemctl status synapse
```

### 6. 配置 Nginx

```bash
# 复制 nginx 配置
sudo cp deployment/nginx-synapse.conf /etc/nginx/sites-available/synapse
sudo ln -s /etc/nginx/sites-available/synapse /etc/nginx/sites-enabled/

# 删除默认配置
sudo rm /etc/nginx/sites-enabled/default

# 获取 SSL 证书
sudo certbot --nginx -d your-domain.com

# 测试配置并重启
sudo nginx -t
sudo systemctl restart nginx
```

---

## 数据库迁移

如果你有现有的 Synapse 实例，需要运行数据库迁移来添加好友功能表：

```bash
# 对于 Docker 部署
docker-compose exec synapse python -m synapse.app.homeserver --config-path /data/homeserver.yaml --run-migrations

# 对于原生部署
sudo -u synapse /opt/synapse/venv/bin/python -m synapse.app.homeserver --config-path /etc/synapse/homeserver.yaml --run-migrations
```

## 创建用户

```bash
# Docker 部署
docker-compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008

# 原生部署
sudo -u synapse /opt/synapse/venv/bin/register_new_matrix_user -c /etc/synapse/homeserver.yaml http://localhost:8008
```

## 监控和维护

### 日志查看

```bash
# Docker 部署
docker-compose logs -f synapse
docker-compose logs -f postgres

# 原生部署
sudo journalctl -u synapse -f
sudo tail -f /var/log/synapse/homeserver.log
```

### 备份

```bash
# 数据库备份
pg_dump -h localhost -U synapse synapse > synapse_backup_$(date +%Y%m%d).sql

# 媒体文件备份
tar -czf media_backup_$(date +%Y%m%d).tar.gz /var/lib/synapse/media/
```

### 更新

```bash
# Docker 部署更新
docker-compose pull
docker-compose up -d

# 原生部署更新
sudo -u synapse -s
source /opt/synapse/venv/bin/activate
pip install --upgrade matrix-synapse[postgres,redis]
sudo systemctl restart synapse
```

## 故障排除

### 常见问题

1. **端口冲突**
   ```bash
   sudo netstat -tlnp | grep :8008
   ```

2. **权限问题**
   ```bash
   sudo chown -R synapse:synapse /opt/synapse
   sudo chown -R synapse:synapse /var/lib/synapse
   ```

3. **数据库连接问题**
   ```bash
   sudo -u synapse psql -h localhost -U synapse synapse
   ```

4. **SSL 证书问题**
   ```bash
   sudo certbot renew --dry-run
   ```

### 性能优化

1. **PostgreSQL 优化**
   ```sql
   -- 在 PostgreSQL 中执行
   ALTER SYSTEM SET shared_buffers = '256MB';
   ALTER SYSTEM SET effective_cache_size = '1GB';
   ALTER SYSTEM SET maintenance_work_mem = '64MB';
   SELECT pg_reload_conf();
   ```

2. **Synapse 配置优化**
   ```yaml
   # 在 homeserver.yaml 中添加
   caches:
     global_factor: 2.0
   
   federation_sender_instances:
     - federation_sender1
   
   instance_map:
     federation_sender1:
       host: localhost
       port: 8009
   ```

## 安全建议

1. **定期更新系统和软件**
2. **使用强密码和密钥**
3. **配置防火墙规则**
4. **启用日志监控**
5. **定期备份数据**
6. **限制管理员权限**

## API 测试

部署完成后，可以测试好友管理 API：

```bash
# 获取访问令牌
curl -X POST https://your-domain.com/_matrix/client/r0/login \
  -H "Content-Type: application/json" \
  -d '{
    "type": "m.login.password",
    "user": "@username:your-domain.com",
    "password": "password"
  }'

# 发送好友请求
curl -X POST https://your-domain.com/_matrix/client/v1/friends/request \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "@friend:your-domain.com",
    "message": "Hello, let's be friends!"
  }'

# 获取好友列表
curl -X GET https://your-domain.com/_matrix/client/v1/friends \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

## 支持和文档

- [Synapse 官方文档](https://matrix-org.github.io/synapse/)
- [Matrix 规范](https://spec.matrix.org/)
- [Element 客户端](https://element.io/)

---

**注意**: 请将所有示例中的 `your-domain.com` 替换为你的实际域名，将密码替换为安全的随机密码。