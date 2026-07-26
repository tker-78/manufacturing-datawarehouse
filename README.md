# Usage

```
docker compose up -d
docker compose run --rm dbt init manufacturing_datawarehouse --skip-profile-setup
docker compose run --rm dbt mv manufacturing_datawarehouse dbt
```

dbt docs

```
docker compose run --rm dbt docs generate
docker compose run --rm --service-ports dbt dbt docs serve --host 0.0.0.0
```



