# Parquet シグナルデータ取り込み設計

## 1. 目的

このドキュメントは、Data Lake 上の Parquet ファイルに保存されたリアルタイム系シグナルデータを、1分粒度に集計し、PostgreSQL ベースの DWH ステージングテーブルへ格納するためのデータパイプライン設計をまとめる。

本パイプラインでは、Parquet の読み取りと1分集計を Python + DuckDB で実行し、集計結果を PostgreSQL に upsert する。  
その後の device / signal の紐付け、dimension / fact / mart の構築、テスト、ドキュメント生成は dbt が担当する。

---

## 2. 対象範囲

本設計の対象は以下の処理である。
```
text
Data Lake raw Parquet
  ↓
Python ingestion process
  ↓
DuckDB read_parquet + aggregation
  ↓
PostgreSQL temporary table
  ↓
PostgreSQL staging table upsert
  ↓
dbt models
```
このパイプラインは Prefect によってオーケストレーションされ、1分周期などの短い間隔で定期実行することを想定する。

---

## 3. 役割分担

## 3.1 Python Ingestion Process

Python の ingestion 処理は以下を担当する。

- 対象 Parquet ファイルの検知
- DuckDB による Parquet ファイルの読み取り
- シグナルデータの1分粒度集計
- psycopg による PostgreSQL 接続
- PostgreSQL temporary table への集計結果ロード
- PostgreSQL staging table への upsert
- ingestion manifest の更新
- エラーハンドリング
- 冪等な再実行制御

---

## 3.2 DuckDB

DuckDB は以下を担当する。

- Parquet ファイルの直接読み取り
- SQL による変換処理
- 以下のキーによる1分粒度集計
```
text
device_id
signal_id
event_time_minute
```
DuckDB は Python ingestion process 内で動作する組み込み分析エンジンとして利用する。

---

## 3.3 PostgreSQL

PostgreSQL は以下を担当する。

- 1分集計済み staging data の永続化
- ingestion metadata の永続化
- upsert のための unique constraint / primary key の提供
- downstream dbt models の source としてのデータ提供

---

## 3.4 Prefect

Prefect は以下を担当する。

- ingestion flow のスケジューリング
- 定期実行
- retry 制御
- ログ管理
- 同時実行の防止
- ingestion job の可観測性確保

---

## 3.5 dbt

dbt は以下を担当する。

- PostgreSQL staging table を source として参照
- DWH 変換ロジックの実装
- device / signal の紐付け
- intermediate model の作成
- dimension / fact / mart の作成
- dbt test の実行
- dbt docs の生成

dbt は、ファイル検知、manifest 管理、低レベルな ingestion 制御は担当しない。

---

## 4. 全体アーキテクチャ
```
text
┌──────────────────────────────┐
│ Data Lake                    │
│ raw_parquet/signals/*.parquet│
└───────────────┬──────────────┘
                │
                │ every 1 minute
                ▼
┌──────────────────────────────┐
│ Prefect Flow                 │
│ ingest_parquet_signals_1min  │
└───────────────┬──────────────┘
                │
                ▼
┌──────────────────────────────┐
│ Python Ingestion Process      │
│ - detect files                │
│ - acquire lock                │
│ - call DuckDB                 │
│ - copy to PostgreSQL temp     │
│ - upsert staging table        │
│ - update manifest             │
└───────────────┬──────────────┘
                │
                ▼
┌──────────────────────────────┐
│ DuckDB                       │
│ read_parquet()               │
│ aggregate by one minute      │
└───────────────┬──────────────┘
                │
                ▼
┌──────────────────────────────┐
│ PostgreSQL                   │
│ ingestion.parquet_manifest   │
│ staging.stg_signal_1min      │
└───────────────┬──────────────┘
                │
                ▼
┌──────────────────────────────┐
│ dbt                          │
│ source → staging → marts     │
└──────────────────────────────┘
```
---

## 5. データフロー

## 5.1 Step 1: Parquet ファイル検知

ingestion process は、設定された Data Lake path をスキャンし、新規または処理対象となる Parquet ファイルを検知する。

想定ディレクトリ構成例:
```
text
data_lake/
  raw_parquet/
    signals/
      dt=2026-08-02/
        hour=10/
          part-0001.parquet
          part-0002.parquet
```
検知したファイルは ingestion manifest table と照合し、二重処理を防止する。

---

## 5.2 Step 2: 実行ロック取得

処理開始前に、同時実行を防ぐための lock を取得する。

推奨方式:
```
text
PostgreSQL advisory lock
```
既に別の flow が実行中の場合は、以下のどちらかの挙動にする。

- 処理せず正常終了する
- 一定時間だけ待機し、取得できなければ安全に失敗する

1分周期で flow を実行する場合、前回実行が完了していない可能性があるため、同時実行防止は必須である。

---

## 5.3 Step 3: DuckDB による Parquet 読み取りと1分集計

DuckDB で Parquet ファイルを直接読み取り、1分粒度に集計する。

論理的な集計キー:
```
text
device_id
signal_id
event_time_minute
```
推奨する集計項目:
```
text
max_value
min_value
avg_value
record_count
first_event_timestamp
last_event_timestamp
latest_batch_id
```
---

## 5.4 Step 4: PostgreSQL temporary table へのロード

Python process は、DuckDB の集計結果を PostgreSQL に転送する。

推奨方式:
```
text
DuckDB result
  ↓
Python stream / Arrow / rows
  ↓
PostgreSQL temporary table
```
件数が少ない場合は batched insert でもよい。  
件数が多くなる場合は PostgreSQL の `COPY` を利用する。

---

## 5.5 Step 5: PostgreSQL staging table への upsert

temporary table へのロード後、永続化先の staging table に対して upsert を行う。

主キー:
```
text
device_id
signal_id
event_time_minute
```
このキーにより、同じ1分バケットを再集計した場合でも安全に更新できる。

---

## 5.6 Step 6: Manifest 更新

upsert が成功したら ingestion manifest を更新する。

manifest には以下を記録する。

- 検知したファイル
- 処理対象となったファイル
- 処理開始時刻
- 処理完了時刻
- 処理成功・失敗ステータス
- 処理行数
- batch_id
- エラーメッセージ

---

## 5.7 Step 7: downstream dbt models の実行

staging table の更新後、Prefect から必要に応じて dbt models を実行する。

対象例:
```
text
staging source models
intermediate signal mapping models
fact signal models
```
---

## 6. PostgreSQL テーブル設計

## 6.1 Staging Table

推奨テーブル:
```
text
staging.stg_signal_1min
```
推奨カラム:

| Column | Type | Description |
|---|---|---|
| `device_id` | text | source data 上の device 識別子 |
| `signal_id` | text | source data 上の signal 識別子 |
| `event_time_minute` | timestamp | event_timestamp を1分単位に切り捨てた時刻 |
| `max_value` | double precision | 1分バケット内の最大値 |
| `min_value` | double precision | 1分バケット内の最小値 |
| `avg_value` | double precision | 1分バケット内の平均値 |
| `record_count` | integer | 1分バケット内の raw record 件数 |
| `first_event_timestamp` | timestamp | 1分バケット内の最初の event timestamp |
| `last_event_timestamp` | timestamp | 1分バケット内の最後の event timestamp |
| `latest_batch_id` | bigint | 1分バケットに含まれる最新 batch_id |
| `updated_at` | timestamp | staging row の更新時刻 |

推奨制約:
```
text
primary key (device_id, signal_id, event_time_minute)
```
---

## 6.2 Manifest Table

推奨テーブル:
```
text
ingestion.parquet_file_manifest
```
推奨カラム:

| Column | Type | Description |
|---|---|---|
| `source_file` | text | Parquet ファイルパス |
| `file_size` | bigint | ファイルサイズ |
| `file_modified_at` | timestamp | source file の更新時刻 |
| `file_hash` | text | ファイル同一性確認用 hash |
| `detected_at` | timestamp | ファイル検知時刻 |
| `started_at` | timestamp | 処理開始時刻 |
| `loaded_at` | timestamp | 処理完了時刻 |
| `batch_id` | bigint | ingestion batch identifier |
| `status` | text | detected, processing, loaded, failed など |
| `row_count` | bigint | 処理行数 |
| `error_message` | text | 失敗時のエラー詳細 |

推奨 status 値:
```
text
detected
processing
loaded
failed
skipped
```
---

## 7. 差分処理方針

## 7.1 基本方針

本パイプラインでは、単純に新規集計行を append するのではなく、同じ1分バケットを再計算できるようにする。

staging table の upsert key:
```
text
device_id
signal_id
event_time_minute
```
このキーにより、遅延到着データや再処理に対応する。

---

## 7.2 Lookback Window 方式

初期実装では lookback window 方式を推奨する。

例:
```
text
実行周期: 1分
lookback window: 15分
```
各実行では以下を行う。
```
text
1. 処理対象 window を決定する
2. window 内に event_timestamp を持つ可能性がある Parquet を読み取る
3. window 内の raw records を1分粒度に集計する
4. staging.stg_signal_1min に upsert する
```
この方式により、lookback window 内の遅延到着データに対応できる。

---

## 7.3 Affected Keys 方式

より正確な実装として affected keys 方式がある。
```
text
1. 新規ファイルを検知する
2. 新規ファイルから distinct device_id, signal_id, event_time_minute を抽出する
3. 該当 key に関係する全 source records を再読み取りする
4. 集計値を再計算する
5. staging table に upsert する
```
Lookback window 方式より正確だが、実装は複雑になる。

初期段階では lookback window 方式で開始し、必要に応じて affected keys 方式に移行するのが望ましい。

---

## 8. 冪等性

ingestion pipeline は冪等である必要がある。

同じ flow が再実行されても安全である条件は以下。

- 処理対象ファイルが manifest table で管理されている
- staging table に primary key がある
- staging table への書き込みが upsert である
- data upsert と manifest update が可能な範囲で transaction 管理されている

staging data の冪等性 key:
```
text
device_id
signal_id
event_time_minute
```
manifest data の冪等性 key:
```
text
source_file
```
---

## 9. エラーハンドリング

推奨するエラーハンドリング方針:

| Failure Point | Recommended Handling |
|---|---|
| ファイル検知失敗 | flow を失敗させ retry |
| Parquet 読み取り失敗 | 対象ファイルを failed として記録 |
| DuckDB 集計失敗 | flow を失敗させ retry |
| PostgreSQL 接続失敗 | flow を失敗させ retry |
| temporary table load 失敗 | transaction rollback |
| upsert 失敗 | transaction rollback |
| manifest update 失敗 | 可能な範囲で transaction rollback |
| dbt run 失敗 | downstream step を failed とし、ingestion 結果は保持 |

失敗したファイルは manifest table 上で確認可能にし、手動または自動で再処理できるようにする。

---

## 10. 同時実行制御

1分周期で flow を実行するため、同時実行を防ぐ必要がある。

推奨方式:

1. PostgreSQL advisory lock
2. Prefect concurrency limit
3. PostgreSQL advisory lock と Prefect concurrency limit の併用

推奨挙動:
```
text
If lock cannot be acquired:
  skip this run
```
これにより、同じ Parquet ファイルの二重処理や staging table への競合 upsert を避ける。

---

## 11. スケジューリング

推奨 Prefect schedule:
```
text
Every 1 minute
```
推奨 flow 名:
```
text
ingest_parquet_signals_1min
```
推奨 task 構成:
```
text
acquire_lock
detect_parquet_files
register_manifest
determine_processing_window
aggregate_parquet_1min
copy_to_postgres_temp
upsert_staging_table
update_manifest
run_dbt_models
release_lock
```
---

## 12. dbt 連携

ingestion 完了後、dbt は PostgreSQL の staging table を source として扱う。

source 定義例:
```
yaml
version: 2

sources:
  - name: staging
    schema: staging
    description: "Ingested staging tables"
    tables:
      - name: stg_signal_1min
        description: "Parquet ファイルから取り込まれた1分粒度のシグナル集計データ"
        columns:
          - name: device_id
            tests:
              - not_null

          - name: signal_id
            tests:
              - not_null

          - name: event_time_minute
            tests:
              - not_null

          - name: record_count
            tests:
              - not_null
```
downstream dbt models では以下を担当する。

- device mapping
- signal mapping
- data quality classification
- fact table 作成
- mart table 作成

---

## 13. 推奨技術スタック

| Area | Technology |
|---|---|
| Orchestration | Prefect |
| Ingestion language | Python |
| Parquet query engine | DuckDB |
| PostgreSQL client | psycopg |
| Bulk load | PostgreSQL COPY |
| DWH storage | PostgreSQL |
| Transformation / modeling | dbt |
| Configuration | environment variables |
| Logging | Prefect logs + structured application logs |

---

## 14. 設定項目

推奨 environment variables:
```
text
MDG_DATABASE_URL
PARQUET_SIGNAL_BASE_PATH
PARQUET_LOOKBACK_MINUTES
PREFECT_FLOW_NAME
DBT_PROJECT_DIR
DBT_PROFILES_DIR
```
設定例:
```
dotenv
MDG_DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:5432/dwh
PARQUET_SIGNAL_BASE_PATH=/data-lake/raw_parquet/signals
PARQUET_LOOKBACK_MINUTES=15
PREFECT_FLOW_NAME=ingest_parquet_signals_1min
DBT_PROJECT_DIR=/usr/app/dbt
DBT_PROFILES_DIR=/root/.dbt
```
---

## 15. 初期実装計画

## 15.1 Phase 1: Minimal Ingestion

- PostgreSQL schema を作成する
  - `staging`
  - `ingestion`
- staging table を作成する
  - `staging.stg_signal_1min`
- manifest table を作成する
  - `ingestion.parquet_file_manifest`
- Python ingestion script を実装する
  - DuckDB で Parquet を読む
  - 1分粒度に集計する
  - PostgreSQL に upsert する
- 手動実行で検証する

---

## 15.2 Phase 2: Prefect Orchestration

- ingestion script を Prefect flow 化する
- retry policy を追加する
- PostgreSQL advisory lock を追加する
- structured logs を追加する
- 1分周期で schedule する

---

## 15.3 Phase 3: dbt Integration

- `staging.stg_signal_1min` の dbt source 定義を追加する
- downstream staging / intermediate / mart models を作成する
- dbt tests を追加する
- ingestion 完了後に Prefect から dbt を実行する

---

## 15.4 Phase 4: Operational Hardening

- file manifest の retry handling を追加する
- alerting を追加する
- metrics を追加する
- late-arrival monitoring を追加する
- unmapped device / signal monitoring を追加する
- PostgreSQL COPY による bulk load を最適化する

---

## 16. 設計判断

## 16.1 ingestion を dbt から分離する理由

Parquet ingestion process には以下が必要である。

- ファイル検知
- manifest 管理
- retry 制御
- lock 制御
- temporary table loading
- upsert orchestration
- operational logging

これらは dbt よりも Python + Prefect で扱う方が適している。

dbt は、PostgreSQL にデータが landing した後の SQL-based DWH transformations に集中させる。

---

## 16.2 DuckDB を使う理由

DuckDB は Parquet ファイルを直接かつ効率的に読み取れる。

そのため、raw events をすべて PostgreSQL にロードせずに、Data Lake 上の Parquet から直接1分集計を作成できる。

---

## 16.3 PostgreSQL temporary table を使う理由

temporary table は、staging table へ upsert する前の loading buffer として利用する。

利点:

- bulk load しやすい
- transaction 管理しやすい
- upsert SQL が単純になる
- row-by-row insert を避けられる
- 失敗時に rollback しやすい

---

## 16.4 upsert が必要な理由

同じ1分バケットが再計算される可能性があるため、upsert が必要である。

再計算が発生するケース:

- 遅延到着データ
- retry processing
- duplicate flow execution
- file reprocessing
- lookback window processing

---

## 17. まとめ

推奨パイプラインは以下である。
```
text
Python
  DuckDB で read_parquet + aggregate
  psycopg で PostgreSQL 接続
  temp table に COPY
  staging table に upsert
  manifest 更新

Prefect
  1分周期で flow 実行
  retry
  logging
  lock

dbt
  PostgreSQL staging table を source として参照
  DWH モデリングを実行
```
この設計により、以下の責務を明確に分離できる。
```
text
ingestion:
  Parquet ファイルの検知、読み取り、集計、PostgreSQL への格納

orchestration:
  定期実行、retry、lock、logging、monitoring

DWH modeling:
  source 定義、mapping、dimension / fact / mart 作成、test、docs
```
リアルタイム寄りの Parquet データを micro-batch として安定的に取り込みつつ、PostgreSQL DWH と dbt による分析基盤へ自然に接続できる構成である。
