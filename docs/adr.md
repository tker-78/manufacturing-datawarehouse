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

重量 = 長さ x 厚み x 比重
の式を使って長さを算出する。


### 設計判断

アルミの比重は2.7g/cmだから、

```
長さ = 重量 / (厚み x 2.7)
```

この計算をintermediateレイヤで行う。



