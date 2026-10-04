# Art Direction / Visual Pipeline

## 1. 当前美术目标

优先级：

1. 角色可信
2. 场景有生活感
3. UI 像一扇窗
4. 动态足够让画面“活着”
5. 3D 作为世界升级，不成为 Demo 风险

---

## 2. 当前图片背景方案

当前仓库已经有多组背景图和 `lin-ruoxi` 角色资产。

图片背景完全可以作为 Submission Build 的正式方案。

不要因为“比赛叫 World Building”就强行把所有背景换成高面数 3D。

背景图 + 角色 + 动态物件 + 灯光 / 粒子 + 状态变化，本身就可以构成有世界感的场景。

---

## 3. 2.5D 升级

如果时间允许：

```text
Background
 ├─ Far
 ├─ Mid
 ├─ Near
 └─ Character
```

配合轻微 Parallax。

可增加：

- 窗外雨
- 灯光变化
- 咖啡蒸汽
- 屏幕光
- 树叶 / 人影
- 角色呼吸

这些低成本动态比增加大量高模更有价值。

---

## 4. Marble / Tripo 资产原则

Marble 生成的模型可能面数较高。

处理顺序：

```text
Generate
 ↓
Import GLB
 ↓
Measure
 ├─ Triangle count
 ├─ Material count
 ├─ Texture memory
 └─ Draw calls
 ↓
Optimize
 ├─ Decimate
 ├─ LOD
 ├─ Atlas / merge materials
 └─ Texture compression
 ↓
Runtime format
```

不要先假设“面数高一定不能用”。必须实测。

---

## 5. GLB → MDL

仓库当前已经存在 `.mdl` 资产，因此 MDL 是实际运行管线的一部分。

推荐资产流：

```text
Marble / Tripo
      ↓
     GLB
      ↓
  Validation
      ↓
 Optimization
      ↓
    MDL
      ↓
 Engine / Maker
```

转换工具和具体命令属于工程实现，不写死在产品设计里。

---

## 6. 两天内美术禁止扩张

不要增加：

- 大地图
- 大量 NPC
- 复杂建筑群
- 100 个可交互物件
- 全场景实时生成
- 高成本角色二套衣服

优先做一个看起来完成度高的小空间。
