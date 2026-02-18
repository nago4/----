-- PostgreSQL 17 実行計画(EXPLAIN) 深掘りガイド
-- 実験環境構築スクリプト

-- クリーンアップ
DROP TABLE IF EXISTS players CASCADE;
DROP TABLE IF EXISTS guilds CASCADE;

-- ギルドテーブル（親テーブル）
CREATE TABLE guilds (
    id INT PRIMARY KEY,
    guild_name TEXT NOT NULL,
    region TEXT NOT NULL,
    founded_at TIMESTAMP NOT NULL
);

-- プレイヤーテーブル（子テーブル）
CREATE TABLE players (
    id INT PRIMARY KEY,
    name TEXT NOT NULL,
    level INT NOT NULL,
    guild_id INT REFERENCES guilds(id),
    login_count INT DEFAULT 0,
    last_login TIMESTAMP,
    created_at TIMESTAMP NOT NULL
);

-- ギルドデータ(50件) を挿入
INSERT INTO guilds 
SELECT 
    i, 
    'Guild_' || i, 
    (ARRAY['Tokyo', 'Osaka', 'Nagoya', 'Fukuoka', 'Sapporo'])[floor(random()*5)+1],
    '2023-01-01 00:00:00'::timestamp + (random() * interval '365 days')
FROM generate_series(1, 50) i;

-- プレイヤーデータ(10万件) を挿入
-- 現実的なレベル分布：初心者30%、中級者40%、上級者30%
INSERT INTO players
SELECT 
    i, 
    'Player_' || i, 
    CASE 
        WHEN random() < 0.3 THEN floor(random() * 30 + 1)
        WHEN random() < 0.7 THEN floor(random() * 40 + 31)
        ELSE floor(random() * 30 + 71)
    END,
    CASE 
        WHEN random() < 0.9 THEN floor(random() * 50 + 1)
        ELSE NULL
    END,
    floor(random() * 500),
    CASE 
        WHEN random() < 0.8 THEN '2024-01-01 00:00:00'::timestamp + (random() * interval '365 days')
        ELSE NULL
    END,
    '2023-01-01 00:00:00'::timestamp + (random() * interval '730 days')
FROM generate_series(1, 100000) i;

-- 統計情報を最新化（必須）
ANALYZE guilds;
ANALYZE players;

-- データが正しく入ったか確認
SELECT 
    'guilds' as table_name, 
    COUNT(*) as record_count 
FROM guilds
UNION ALL
SELECT 
    'players' as table_name, 
    COUNT(*) as record_count 
FROM players;

-- レベル分布の確認
SELECT 
    CASE 
        WHEN level BETWEEN 1 AND 30 THEN '初心者(1-30)'
        WHEN level BETWEEN 31 AND 70 THEN '中級者(31-70)'
        ELSE '上級者(71-100)'
    END as category,
    COUNT(*) as player_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM players), 1) || '%' as ratio
FROM players
GROUP BY category
ORDER BY MIN(level);

-- ギルド所属状況の確認
SELECT 
    CASE 
        WHEN guild_id IS NULL THEN '無所属'
        ELSE '所属中'
    END as status,
    COUNT(*) as player_count
FROM players
GROUP BY status;
