-- Synapse Friends 功能数据库初始化脚本
-- 创建好友管理相关的表结构

-- 启用 RLS (Row Level Security)
ALTER DATABASE postgres SET row_security = on;

-- 创建好友关系表
CREATE TABLE IF NOT EXISTS user_friendships (
    id BIGSERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    friend_user_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_ts BIGINT NOT NULL,
    updated_ts BIGINT NOT NULL,
    UNIQUE(user_id, friend_user_id),
    CHECK (user_id != friend_user_id),
    CHECK (status IN ('active', 'blocked', 'removed'))
);

-- 创建好友请求表
CREATE TABLE IF NOT EXISTS friend_requests (
    id BIGSERIAL PRIMARY KEY,
    sender_user_id TEXT NOT NULL,
    target_user_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    message TEXT,
    created_ts BIGINT NOT NULL,
    updated_ts BIGINT NOT NULL,
    expires_ts BIGINT,
    UNIQUE(sender_user_id, target_user_id),
    CHECK (sender_user_id != target_user_id),
    CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled', 'expired'))
);

-- 创建好友设置表
CREATE TABLE IF NOT EXISTS friend_settings (
    user_id TEXT PRIMARY KEY,
    allow_friend_requests BOOLEAN NOT NULL DEFAULT true,
    auto_accept_friends BOOLEAN NOT NULL DEFAULT false,
    max_friends INTEGER NOT NULL DEFAULT 1000,
    privacy_level TEXT NOT NULL DEFAULT 'normal',
    created_ts BIGINT NOT NULL,
    updated_ts BIGINT NOT NULL,
    CHECK (max_friends >= 0 AND max_friends <= 10000),
    CHECK (privacy_level IN ('public', 'normal', 'private'))
);

-- 创建索引以提高查询性能
CREATE INDEX IF NOT EXISTS idx_user_friendships_user_id ON user_friendships(user_id);
CREATE INDEX IF NOT EXISTS idx_user_friendships_friend_user_id ON user_friendships(friend_user_id);
CREATE INDEX IF NOT EXISTS idx_user_friendships_status ON user_friendships(status);
CREATE INDEX IF NOT EXISTS idx_user_friendships_created_ts ON user_friendships(created_ts);

CREATE INDEX IF NOT EXISTS idx_friend_requests_sender_user_id ON friend_requests(sender_user_id);
CREATE INDEX IF NOT EXISTS idx_friend_requests_target_user_id ON friend_requests(target_user_id);
CREATE INDEX IF NOT EXISTS idx_friend_requests_status ON friend_requests(status);
CREATE INDEX IF NOT EXISTS idx_friend_requests_created_ts ON friend_requests(created_ts);
CREATE INDEX IF NOT EXISTS idx_friend_requests_expires_ts ON friend_requests(expires_ts);

CREATE INDEX IF NOT EXISTS idx_friend_settings_allow_requests ON friend_settings(allow_friend_requests);

-- 启用 RLS 策略
ALTER TABLE user_friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE friend_settings ENABLE ROW LEVEL SECURITY;

-- 创建 RLS 策略 - 用户只能访问自己相关的数据
CREATE POLICY "Users can view their own friendships" ON user_friendships
    FOR SELECT USING (user_id = current_setting('app.current_user_id', true) OR friend_user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Users can insert their own friendships" ON user_friendships
    FOR INSERT WITH CHECK (user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Users can update their own friendships" ON user_friendships
    FOR UPDATE USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Users can delete their own friendships" ON user_friendships
    FOR DELETE USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Users can view friend requests involving them" ON friend_requests
    FOR SELECT USING (sender_user_id = current_setting('app.current_user_id', true) OR target_user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Users can insert their own friend requests" ON friend_requests
    FOR INSERT WITH CHECK (sender_user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Users can update friend requests involving them" ON friend_requests
    FOR UPDATE USING (sender_user_id = current_setting('app.current_user_id', true) OR target_user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Users can delete their own friend requests" ON friend_requests
    FOR DELETE USING (sender_user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Users can view their own settings" ON friend_settings
    FOR SELECT USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Users can insert their own settings" ON friend_settings
    FOR INSERT WITH CHECK (user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Users can update their own settings" ON friend_settings
    FOR UPDATE USING (user_id = current_setting('app.current_user_id', true));

CREATE POLICY "Users can delete their own settings" ON friend_settings
    FOR DELETE USING (user_id = current_setting('app.current_user_id', true));

-- 授予权限给 anon 和 authenticated 角色
GRANT SELECT, INSERT, UPDATE, DELETE ON user_friendships TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON friend_requests TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON friend_settings TO anon, authenticated;

-- 授予序列权限
GRANT USAGE, SELECT ON SEQUENCE user_friendships_id_seq TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE friend_requests_id_seq TO anon, authenticated;

-- 创建函数来清理过期的好友请求
CREATE OR REPLACE FUNCTION cleanup_expired_friend_requests()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    UPDATE friend_requests 
    SET status = 'expired', updated_ts = extract(epoch from now()) * 1000
    WHERE status = 'pending' 
    AND expires_ts IS NOT NULL 
    AND expires_ts < extract(epoch from now()) * 1000;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 创建触发器函数来自动更新 updated_ts
CREATE OR REPLACE FUNCTION update_updated_ts_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_ts = extract(epoch from now()) * 1000;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 为表创建触发器
CREATE TRIGGER update_user_friendships_updated_ts
    BEFORE UPDATE ON user_friendships
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_ts_column();

CREATE TRIGGER update_friend_requests_updated_ts
    BEFORE UPDATE ON friend_requests
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_ts_column();

CREATE TRIGGER update_friend_settings_updated_ts
    BEFORE UPDATE ON friend_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_ts_column();

-- 插入一些示例数据（可选）
-- 注意：在生产环境中可能不需要这些示例数据

-- 创建视图来简化查询
CREATE OR REPLACE VIEW user_friends_view AS
SELECT 
    uf.user_id,
    uf.friend_user_id,
    uf.status,
    uf.created_ts,
    uf.updated_ts
FROM user_friendships uf
WHERE uf.status = 'active';

CREATE OR REPLACE VIEW pending_friend_requests_view AS
SELECT 
    fr.id,
    fr.sender_user_id,
    fr.target_user_id,
    fr.message,
    fr.created_ts,
    fr.expires_ts
FROM friend_requests fr
WHERE fr.status = 'pending'
AND (fr.expires_ts IS NULL OR fr.expires_ts > extract(epoch from now()) * 1000);

-- 授予视图权限
GRANT SELECT ON user_friends_view TO anon, authenticated;
GRANT SELECT ON pending_friend_requests_view TO anon, authenticated;

-- 完成初始化
SELECT 'Friends tables initialized successfully' AS result;