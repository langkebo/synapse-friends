# Synapse Matrix Server with Friends Feature

这是一个基于官方 Synapse Matrix 服务器的增强版本，添加了朋友管理功能。

## 新增功能

### 朋友管理系统
- 发送和接收好友请求
- 管理好友列表
- 好友状态查看
- 隐私设置控制

### API 端点
- `POST /_matrix/client/r0/friends/request` - 发送好友请求
- `GET /_matrix/client/r0/friends/requests` - 获取好友请求列表
- `POST /_matrix/client/r0/friends/accept` - 接受好友请求
- `POST /_matrix/client/r0/friends/reject` - 拒绝好友请求
- `GET /_matrix/client/r0/friends` - 获取好友列表
- `DELETE /_matrix/client/r0/friends/{user_id}` - 删除好友
- `GET /_matrix/client/r0/friends/settings` - 获取隐私设置
- `PUT /_matrix/client/r0/friends/settings` - 更新隐私设置

## 部署方式

### 1. Docker 部署（推荐）

#### 本地部署
```bash
cd deployment
chmod +x deploy.sh
./deploy.sh
```

#### Supabase 部署
```bash
cd deployment
chmod +x deploy-supabase.sh
./deploy-supabase.sh
```

### 2. 原生部署
参考 `deployment/DEPLOYMENT_GUIDE.md` 获取详细的 Ubuntu 部署指南。

## 配置文件

- `deployment/docker-compose.yml` - 本地 Docker 部署配置
- `deployment/docker-compose.supabase.yml` - Supabase 部署配置
- `deployment/DEPLOYMENT_GUIDE.md` - Ubuntu 部署指南
- `supabase/migrations/001_init_friends_tables.sql` - 数据库迁移文件

## 环境要求

- Docker & Docker Compose
- Python 3.11+
- PostgreSQL 13+
- Redis (可选，用于缓存)

## 安全特性

- Row Level Security (RLS) 数据库策略
- 用户隐私设置控制
- 好友请求过期机制
- 完整的权限验证

## 开发

本项目基于官方 Synapse Matrix 服务器开发，添加了朋友管理功能模块：

- `synapse/rest/client/friends.py` - REST API 处理器
- `synapse/handlers/friends.py` - 业务逻辑处理
- `synapse/storage/databases/main/friends.py` - 数据库操作

## 许可证

本项目遵循 Apache License 2.0，与官方 Synapse 保持一致。

## 贡献

欢迎提交 Issue 和 Pull Request 来改进朋友管理功能。

## 支持

如有问题，请查看部署指南或提交 Issue。