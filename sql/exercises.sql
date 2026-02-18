-- PostgreSQL 17 実行計画(EXPLAIN) 深掘りガイド
-- 演習・実験用SQLスクリプト

-- ========================================
-- セクション3：EXPLAINの読み方とコスト理論
-- ========================================

-- 【実験1】予測と実測のズレを観察
-- インデックスがない状態での実行計画（予測）
EXPLAIN SELECT * FROM players WHERE level = 50;

-- 実際に実行して実測値を確認
EXPLAIN ANALYZE SELECT * FROM players WHERE level = 50;

-- クエリA（条件が厳しい）
EXPLAIN ANALYZE SELECT * FROM players WHERE level = 100;

-- クエリB（条件が緩い）
EXPLAIN ANALYZE SELECT * FROM players WHERE level >= 1 AND level <= 10;

-- ========================================
-- セクション4：インデックスの真価と限界
-- ========================================

-- インデックス作成前のベンチマーク
EXPLAIN ANALYZE SELECT * FROM players WHERE level = 50;

-- インデックスを作成
DROP INDEX IF EXISTS idx_players_level;
CREATE INDEX idx_players_level ON players(level);

-- インデックス作成後のベンチマーク
EXPLAIN ANALYZE SELECT * FROM players WHERE level = 50;

-- 【実験2】インデックス使用の境界線を探る

-- A: 絞り込みが強い（対象が少ない）
EXPLAIN ANALYZE SELECT * FROM players WHERE level = 100;

-- B: 絞り込みが中程度
EXPLAIN ANALYZE SELECT * FROM players WHERE level BETWEEN 30 AND 70;

-- C: 絞り込みが弱い（対象が多い）
EXPLAIN ANALYZE SELECT * FROM players WHERE level >= 1;

-- インデックスが使えないSQLパターン

-- ❌ 悪い例1：インデックス列に関数を適用
EXPLAIN SELECT * FROM players WHERE LOWER(name) = 'player_100';

-- ❌ 悪い例2：インデックス列に演算
EXPLAIN SELECT * FROM players WHERE level * 2 > 100;

-- ❌ 悪い例3：型変換（実行するとエラーになるためコメントアウト）
-- EXPLAIN SELECT * FROM players WHERE name = 100;
-- ERROR:  演算子が存在しません: text = integer
-- 型が合わないため、インデックスどころか実行すらできない

-- ✅ 良い例1：関数を右辺に
EXPLAIN SELECT * FROM players WHERE name = LOWER('PLAYER_100');

-- ✅ 良い例2：演算を右辺に
EXPLAIN SELECT * FROM players WHERE level > 100 / 2;

-- ========================================
-- セクション5：統計情報とオプティマイザ
-- ========================================

-- テーブル全体の統計
SELECT 
    schemaname,
    relname as tablename,
    n_live_tup as row_count,
    n_dead_tup as dead_rows,
    last_vacuum,
    last_analyze
FROM pg_stat_user_tables 
WHERE relname = 'players';

-- カラムレベルの統計
SELECT 
    attname,
    n_distinct,
    avg_width,
    null_frac
FROM pg_stats 
WHERE tablename = 'players' 
ORDER BY attname;

-- 【実験3】統計情報の影響を観察

-- 1. 100万件の新規プレイヤーを挿入
INSERT INTO players (id, name, level, guild_id, login_count, created_at)
SELECT 
    100000 + i,
    'NewPlayer_' || i,
    floor(random() * 100 + 1),
    floor(random() * 50 + 1),
    0,
    CURRENT_TIMESTAMP
FROM generate_series(1, 100000) i;

-- 2. ANALYZEなしで実行計画を確認
EXPLAIN SELECT * FROM players WHERE level = 50;

-- 3. ANALYZEを実行
ANALYZE players;

-- 4. 実行計画を再確認
EXPLAIN SELECT * FROM players WHERE level = 50;

-- ========================================
-- セクション6：結合アルゴリズム
-- ========================================

-- Nested Loop Join を誘発（特定1プレイヤーのギルド情報）
EXPLAIN ANALYZE 
SELECT p.name, g.guild_name 
FROM players p 
JOIN guilds g ON p.guild_id = g.id 
WHERE p.id = 1;

-- Hash Join を誘発（全プレイヤーとギルドの結合）
EXPLAIN ANALYZE 
SELECT p.name, g.guild_name 
FROM players p 
JOIN guilds g ON p.guild_id = g.id;

-- Merge Join を誘発（複合インデックス作成後）
DROP INDEX IF EXISTS idx_players_guild_level;
CREATE INDEX idx_players_guild_level ON players(guild_id, level);

EXPLAIN ANALYZE 
SELECT p.id, p.name, g.guild_name 
FROM players p 
JOIN guilds g ON p.guild_id = g.id 
ORDER BY p.guild_id, p.level;

-- ========================================
-- セクション7：複合インデックスの設計戦略
-- ========================================

-- 【実験4】インデックスカラム順序の影響

-- 検証クエリ
SELECT * FROM players 
WHERE guild_id = 5 AND level BETWEEN 30 AND 60;

-- パターン1：guild_id が先（良い）
DROP INDEX IF EXISTS idx_guild_level_1;
CREATE INDEX idx_guild_level_1 ON players(guild_id, level);
EXPLAIN ANALYZE SELECT * FROM players WHERE guild_id = 5 AND level BETWEEN 30 AND 60;

-- パターン2：level が先（良くない）
DROP INDEX IF EXISTS idx_guild_level_1;
DROP INDEX IF EXISTS idx_guild_level_2;
CREATE INDEX idx_guild_level_2 ON players(level, guild_id);
EXPLAIN ANALYZE SELECT * FROM players WHERE guild_id = 5 AND level BETWEEN 30 AND 60;

-- ========================================
-- セクション8：最終演習
-- ========================================

-- 【演習1】スロークエリを救え

-- 1. 現状を確認
EXPLAIN ANALYZE 
SELECT name, created_at 
FROM players 
WHERE created_at >= '2023-12-01' 
  AND login_count > 300;

-- 2. 複合インデックスを作成
DROP INDEX IF EXISTS idx_players_created_login;
CREATE INDEX idx_players_created_login ON players(created_at, login_count);

-- 3. 再度実行計画を確認
EXPLAIN ANALYZE 
SELECT name, created_at 
FROM players 
WHERE created_at >= '2023-12-01' 
  AND login_count > 300;

-- 【演習2】インデックスが使われない理由を特定

-- インデックス列に演算を行っているため使われない
EXPLAIN 
SELECT * FROM players WHERE level * 2 > 180;

-- 修正案1：右辺で計算
EXPLAIN ANALYZE 
SELECT * FROM players WHERE level > 180 / 2;

-- 修正案2：型が安全な書き方
EXPLAIN ANALYZE 
SELECT * FROM players WHERE level > 90;

-- 【演習3】結合クエリのチューニング

-- 1. 現状確認（Hash Joinが選ばれる）
EXPLAIN ANALYZE 
SELECT p.id, p.name, p.level, g.guild_name 
FROM players p 
JOIN guilds g ON p.guild_id = g.id 
WHERE p.level >= 50 
ORDER BY p.guild_id, p.level;

-- 2. Merge Joinを誘発するインデックスを作成
-- 前のセクションで既に同じ構成のインデックスが作成されている場合があるため削除
DROP INDEX IF EXISTS idx_players_guild_level;
DROP INDEX IF EXISTS idx_guild_level_1;
DROP INDEX IF EXISTS idx_guild_level_2;
DROP INDEX IF EXISTS idx_players_guild_level_range;
CREATE INDEX idx_players_guild_level_range ON players(guild_id, level);

-- 3. 再度実行計画を確認（Merge Join が選ばれるはず）
EXPLAIN ANALYZE 
SELECT p.id, p.name, p.level, g.guild_name 
FROM players p 
JOIN guilds g ON p.guild_id = g.id 
WHERE p.level >= 50 
ORDER BY p.guild_id, p.level;

-- 【演習4】統計情報とオプティマイザ

-- 1. 大量の新規データを挿入（レベルが高いプレイヤーばかり）
INSERT INTO players (id, name, level, guild_id, login_count, created_at)
SELECT 
    200000 + i,
    'HighLevel_' || i,
    floor(random() * 30 + 71),  -- Lv 71-100 に集中
    floor(random() * 50 + 1),
    floor(random() * 500),
    CURRENT_TIMESTAMP
FROM generate_series(1, 50000) i;

-- 2. ANALYZE なしで実行計画を確認（予測値が古い）
EXPLAIN SELECT * FROM players WHERE level >= 80;

-- 3. ANALYZE を実行
ANALYZE players;

-- 4. 実行計画を再確認（rows 予測値が更新される）
EXPLAIN SELECT * FROM players WHERE level >= 80;
