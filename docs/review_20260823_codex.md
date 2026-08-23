# プロジェクト評価レビュー

- 評価日: 2026-08-23
- 評価者: Codex
- 対象: `manufacturing-datawarehouse`

## 総評

設計思想は良い一方、現状は「完成した分析基盤」ではなく、Phase 2〜3途中のプロトタイプである。

- 完成品としての評価: **4/10**
- 設計途中のポートフォリオとしての評価: **7/10**

staging → intermediate → marts → aggregates の責務分離や、Fact/Dimension、SCD2、粒度、センチネル値、代理時刻といった実務的な論点への取り組みは評価できる。一方で、実行を妨げるモデル・テスト定義の不整合、KPIの意味を変え得る集計ロジック、データ契約と運用実装の不足が残っている。

## 良い点

- staging → intermediate → marts → aggregates のレイヤー構成が分かりやすい。
- Fact/Dimension、SCD2、粒度、センチネル値、代理時刻など、実務で重要な設計論点を扱っている。
- ADRで判断理由を残している。特に、欠損レコードを安易に除外せず、異常として検知する方針は妥当である。
- 合成データの数値を実設備・実在企業に関する業務上の結論として扱わない制約が明記されている。
- Docker Compose定義は構文検証に成功した。

## 主要な指摘事項

### 1. `dbt build`が完走しない可能性が高い

重要度: **Critical**

`dbt/models/staging/stg_pdi.sql` が空であり、有効なモデルSQLになっていない。

また、`dbt/models/intermediate/int_coil_process_duration.sql` は `process_duration_seconds` を生成しているが、`dbt/models/intermediate/__intermediate.yml` のテストは `process_duration_second` を参照している。少なくとも当該テストはDB実行時に存在しない列を参照して失敗する可能性が高い。

参照箇所:

- `dbt/models/staging/stg_pdi.sql`
- `dbt/models/intermediate/int_coil_process_duration.sql:18`
- `dbt/models/intermediate/__intermediate.yml:72`

### 2. 不明な品質状態を完成品に含めている

重要度: **High**

`fact_coil_completion` の次の条件は、`is_rejected = false`だけでなく`is_rejected is null`のレコードも完成品として扱う。

```sql
where is_rejected is not true
```

品質状態が不明なコイルを良品側へ含めるため、生産量、完成率、歩留まりなどを過大評価する可能性がある。「欠損を安全に処理する」という開発計画とも整合していない。

参照箇所:

- `dbt/models/marts/fact_coil_completion.sql:3`

### 3. SCD2を作成しているが、Factが履歴時点のDimensionを参照していない

重要度: **High**

`dim_shift`は`shift_id`と`dbt_valid_from`から履歴行ごとのサロゲートキーを生成している。一方、Fact側は次の条件によって常に現在有効なDimension行へ結合している。

```sql
shift.shift_id = joined.shift_id
and shift.dbt_valid_to is null
```

シフト属性が変更されると、過去の生産実績も現在版のDimensionへ遡及的に付け替わる。この挙動では、SCD2を採用する意義が失われる。Factのイベント時刻が`dbt_valid_from`以上かつ`dbt_valid_to`未満となる履歴行へ結合する設計が必要である。

参照箇所:

- `dbt/models/marts/dim_shift.sql:6`
- `dbt/models/marts/fact_coil_completion.sql:62`
- `dbt/models/marts/fact_coil_rejection.sql:62`

### 4. 時間集計のシフト帰属がシフト別KPIに適さない

重要度: **High**

`agg_hourly_coil_production`は、1時間の途中でシフトが変わった場合、その時間内の全生産を「その時間内で最初のシフト」に帰属させる。

この仕様はYAMLに明記されているものの、シフト別・班別の生産性を測定する用途では誤解を招く。特に、aggregates層を定形ダッシュボード用と位置付けているため、利用者が近似値であることを認識せず使用するリスクがある。

参照箇所:

- `dbt/models/aggregates/agg_hourly_coil_production.sql:22`
- `dbt/models/aggregates/__aggregates.yml:3`

### 5. テストとデータ契約が不足している

重要度: **High**

以下の検証が不足している。

- source freshness
- ソースおよびstagingの主キー一意性
- FactからDimensionへのrelationshipsテスト
- booleanや区分値に対するaccepted values
- 時刻の前後関係などの業務ルール
- モデル契約や列型の保証
- 異常系レコードの隔離と件数監視

YAMLには多数の列が列挙されているが、実際のSQLが生成する列と一致しない箇所も多い。例えば`stg_tracking`のSQLが生成する列は3列だが、YAMLには多数の未実装列が定義されている。列を列挙するだけではテストや契約にならないため、ドキュメントと実装が乖離したままでも検知できない。

参照箇所:

- `dbt/models/staging/stg_tracking.sql`
- `dbt/models/staging/__staging.yml:82`
- `docs/開発計画.md:45`

### 6. 再現可能な起動手順が未完成

重要度: **Medium**

READMEには最低限のコマンドしかなく、次の情報が不足している。

- アーキテクチャ
- データフロー
- 前提条件
- 初期化方法
- seedや合成データの再現条件
- `dbt build`とテスト手順
- 制約事項と既知の未実装範囲
- トラブルシューティング

また、READMEの次のコマンドは、DockerfileにdbtのENTRYPOINTがないため、`docs`を実行ファイルとして起動しようとして失敗する可能性が高い。

```bash
docker compose run --rm dbt docs generate
```

この構成では、次のように先頭の`dbt`が必要である。

```bash
docker compose run --rm dbt dbt docs generate
```

PostgreSQLにはhealthcheckがなく、`depends_on`もサービス起動順しか保証しないため、データ生成処理がDBの接続受付開始前に走る可能性もある。

参照箇所:

- `README.md:1`
- `README.md:31`
- `Dockerfile.dbt`
- `docker-compose.yml:18`

### 7. 開発計画と実装の差が大きい

重要度: **Medium**

開発計画には以下が完成条件または開発目標として記載されているが、リポジトリ内に実装が確認できない。

- Superset
- Prefectによるオーケストレーション
- CI
- 性能計測とクエリプラン評価
- Accumulating Snapshot Fact
- KPI／データ品質ダッシュボード
- Parquet取り込みのPython実装
- 異常系を含む再現可能なテストデータ

`sql/raw_signals_ingestion.sql`も現状は概念実証に近く、Parquet取り込み設計書で要求している平均値、件数、manifest、lookback window、ロック、トランザクション制御などは実装されていない。

参照箇所:

- `docs/開発計画.md:35`
- `docs/開発計画.md:50`
- `docs/parquet_ingestion_design.md`
- `sql/raw_signals_ingestion.sql`

## その他の観察事項

- `fact_coil_completion`は重量に実測値→計算値のフォールバックを使用するが、`fact_coil_rejection`は実測値のみを使用している。良品と不良品で重量集計の欠損方針が異なる。
- `coil_completion_duration`はtrackingの終了時刻と開始時刻から計算される一方、ADR004ではeject timestampの欠損を負値の原因として説明しており、説明と実装の因果関係が一致していない。
- `dim_shift`のYAMLには、実モデルに存在しない名前やスペルミスと思われる列がある。
- PostgreSQLのユーザー名とパスワードがComposeおよびprofilesに固定値で記載されている。ローカル開発専用としては理解できるが、環境変数化されておらず、構成の移植性は低い。
- `README.md`のタイトルが`Userge`となっており、ポートフォリオの入口として完成度を下げている。

## 推奨する改善順序

1. 空モデルと列名不一致を解消し、`dbt build`を確実に成功させる。
2. 完成、リジェクト、不明の状態定義と除外条件を固定する。
3. source、staging、Fact、Dimension間の一意性・必須性・参照整合性テストを追加する。
4. SCD2のFact結合をイベント時点基準にするか、SCD2が不要なら設計を単純化する。
5. シフト別KPIで時間境界をどう扱うか決定し、集計粒度と表示上の制約を明文化する。
6. READMEを完成条件に合わせて再構成する。
7. CIで`dbt deps`、`dbt build`、SQL lintなどを実行する。
8. その後にSuperset、Prefect、性能計測へ進む。

## 検証範囲と制約

以下を読み取り専用で確認した。

- リポジトリ構成とGit追跡対象
- dbtモデル、テスト、snapshot、macro、package定義
- Docker Compose、Dockerfile、profiles
- README、開発計画、ADR、マート設計、Parquet取り込み設計
- `docker compose config --quiet`によるCompose構文検証

評価時点で、未追跡の`config.toml`が存在していた。このファイルを含め、評価中は既存ファイルを変更していない。

実際の`dbt build`は、`target/`やログ、データベースなどへ変更を加えるため、変更禁止という評価条件に従って実行していない。そのため、実行時エラーに関する指摘は静的レビューに基づく。
