# Userge

## パッケージのインストール

- manufacturing-data-generatorを./packages/に保存する。


```
docker compose up -d
# docker compose run --rm dbt dbt init manufacturing_datawarehouse --skip-profile-setup
# docker compose run --rm dbt dbt mv manufacturing_datawarehouse dbt
```

## データの挿入
```
docker compose run --rm mdg mdg generate
```


dbtを実行
```
docker compose run --rm dbt dbt debug
docker compose run --rm dbt dbt run
```



dbt docs

```
docker compose run --rm dbt docs generate
docker compose run --rm --service-ports dbt dbt docs serve --host 0.0.0.0
```



