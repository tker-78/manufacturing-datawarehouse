# ADR

## ADR001

### 問題: sourceデータの不備の扱い

### 背景:

sourceデータの不備により、coilとshiftの紐付けに不備があった。
(shift_idがnullのものが存在)

r_cnvactを確認すると、eject_timestamp_utcが`1970-01-01 00:00:00.000`の
レコードが複数存在した。
このため、対象となるレコードが見つからず、shift_id = NULLで計算されていたことが原因。


### 対応方法の検討: 

shift_id = nullとなったレコードをcoilごと落としてしまうと、
集計が狂う。
そのため、coil_idごと落とすことはせずに、shift_idのnullを検知する
dbt testでパイプラインを失敗させる。



### 設計判断: 

timestampとして、無効な値として過去日付を使用しない。
sourceデータでその扱いをしている場合は、stagingレイヤ取り込み時にnullに変換する。

shift帰属できなかったcoilについては、必要に応じて別テーブルに切り出す。
その場合、下記のように分け、downstreamには正常系のテーブルを用いる
```
int_coil_shift_attribution_base
|
|- int_coil_shift_attribution(正常系)
L- int_coil_shift_attribution_unmatched(異常系)
```


## ADR002

### 問題: coil_lengthのデータがsourceにない

### 背景

coil_lengthのデータがsourceデータに存在しない。

### 対応方法の検討

重量 = 長さ x 厚み x 幅 x 比重
の式を使って長さを算出する。


### 設計判断

アルミの比重は2.7g/cm^3だから、
2.7 * 10^(-3) * 10^6  kg/m^3
= 2.7 * 10^3 kg/m^3


```
長さ = 重量 / (厚み x 幅 x 2.7)
```

この計算をintermediateレイヤで行う。

---

## ADR003

### 問題

data_testでdbt_utils.expression_is_trueで式の一致が失敗する。

### 背景

width, thickness, weightからlengthを計算する式で、

```
expression: "weight = length * thickness * width * 2.7 * 10^(-3)"
```
としたときに、完全一致のテストになるため、桁落ちなどの場合にテストが失敗する。


### 対応方法の検討

許容誤差を設定してテストを実装する。


### 設計判断

```
- name: int_coil_length
    description: |
      Length calculation from its weight and thickness
    data_tests:
      - dbt_utils.expression_is_true:
          arguments:
            expression: >
              abs(
                weight - thickness * width * length * 2.7 * 10^(-3)
              ) < 0.01
```

---

## ADR004

### 問題

fact_coil_completionのcoil_completion_durationが、負の値になっている箇所がある。


### 背景

原因は、データソースのeject_timestamp_utcがnullになっていること。


### 対応方法の検討

このレコード自体を落としてしまうと、生産量などの値に狂いが出る。
しかし、シフトの紐付けはcoil完成のタイミングで行っているため、
このままではシフトの紐付けがされない。

対策としては、シフトの紐付けに用いる代理timestampをintermediateで計算する。

fce_extract_timestamp_utcからdc_z_off_timestamp_utcはだいたい35分かかるから、
それを標準時間と設定する。


```
altenative_eject_timestamp_utc = fce_extract_timestamp_utc + interval '35 minutes'
```

### 設計判断

代理timestampの計算をintermediateに閉じ込めておけば、
その判定ロジックが明確になり、保守性を担保できる。


---

## ADR005

### 問題

martsレイヤの位置づけが曖昧。
martsレイヤにはfact/dimが含まれるが、
BIから扱うデータもmartsに含みたい。

異なるレイヤに属するデータをどちらもmartsと読んでいるため、
構造化が適切になされないリスクがある。

### 背景

Kimball的にはfact/dimこそがデータマート。

ただし、一般的には集計済みのデータを保持している空間のことをデータマートと呼ぶ場合が多い。

### 対応方法の検討

martsレイヤの上に、`aggregates`レイヤを作る。

- martsにはdim/fact
- aggregatesには、集計済みデータ

- martsは
  - aggregatesの元データ
  - BIで探索的分析に扱うデータ
- aggregatesは
  - 定形ダッシュボードから扱うデータ

### 設計判断

✅ Accepted


- martsレイヤの上にaggregatesレイヤを作る。
- ダッシュボード標準化に用いるデータはaggregates

---

## ADR006

### 問題

### 背景

### 対応方法の検討

### 設計判断


---

## ADR007

### 問題

### 背景

### 対応方法の検討

### 設計判断

---

## ADR008

### 問題

### 背景

### 対応方法の検討

### 設計判断
---

## ADR009

### 問題

### 背景

### 対応方法の検討

### 設計判断
