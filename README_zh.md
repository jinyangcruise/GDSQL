<div align="center">

# GDSQL

**Godot 数据库 SQL 工作台插件**

[English](README.md) | **简体中文**

[![Godot](https://img.shields.io/badge/Godot-4.x-478CBF?logo=godot-engine&logoColor=white)](https://godotengine.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Pure GDScript](https://img.shields.io/badge/100%25-GDScript-3b82f6)]()

基于 Godot 引擎 `ConfigFile` 机制的数据库 SQL 工作台。提供可视化的数据库管理界面、Excel 风格的数据编辑、完整的 SQL 查询引擎、MyBatis 风格的 ORM 映射框架（GBatis），以及 AES-256-CBC 数据加密支持。**纯 GDScript 实现，零外部依赖，无需数据库服务器。**

</div>

---

## 功能概览

### SQL 查询引擎
- **完整的 SQL 语法支持**：SELECT / INSERT / UPDATE / DELETE / REPLACE
- **条件查询**：WHERE、AND、OR、IN、NOT IN、BETWEEN、LIKE、IS NULL
- **排序与分组**：ORDER BY、GROUP BY、HAVING
- **分页**：LIMIT、OFFSET
- **连接查询**：LEFT JOIN（支持链式多表连接）
- **联合查询**：UNION ALL
- **子查询**：支持相关子查询与非相关子查询
- **聚合函数**：COUNT、SUM、AVG、MIN、MAX、GROUP_CONCAT 等
- **表达式求值**：SQL 兼容的 null 语义，支持运算、函数调用、类型转换
- **LRU 缓存**：自动缓存最近解析的 SQL 语句（1024 条）

### 可视化数据库工作台
在 Godot 编辑器中以独立主屏形式提供：

- **数据库树浏览器**：以树形结构浏览所有数据库和表
- **数据表查看器**：仿 Excel 表格形式浏览和编辑数据
- **行内编辑**：直接在表格单元格中修改数据，即时生效
- **列宽拖拽**：自由调整列宽，长内容一目了然
- **表结构编辑器**：查看和修改表的列定义、类型、默认值、注释等
- **模式管理**：可视化创建 / 删除 / 编辑数据库和数据表
- **数据导入导出**：支持 CSV、JSON、CFG 格式
- **差异视图**：对比数据表的内容差异，高亮显示增删改
- **SQL 查询编辑器**：编写和执行 SQL 语句，自动记录查询历史
- **查询结果导出**：将查询结果导出为 CSV、JSON 或 CFG 文件

### 智能自动填充
- **最小二乘法数据拟合**：基于已有数据样本，自动预测和填充后续数据
- **支持多种数据类型**：数字、字符串（含数字占位符）、Vector2/3/4、Vector2i/3i/4i、Resource 路径
- **智能模式识别**：自动检测数据中的编号模式（如 `"name_001"`、`"name_002"`），按模式规律填充

### 链式 DAO API
无需编写 XML 映射文件，直接通过 GDScript 链式调用完成数据库操作：

```gdscript
# 查询气血大于100的英雄，按气血降序排列
var result = GDSQL.BaseDao.new()
    .use_db("game_config")
    .select("id, name, hp, mp")
    .from("c_hero")
    .where("hp > 100 AND mp >= 50")
    .order_by("hp")
    .limit(10)
    .query()

# 插入新数据
GDSQL.BaseDao.new()
    .use_db("game_config")
    .insert_into("c_hero")
    .values({"id": 101, "name": "NewHero", "hp": 200})
    .query()

# 更新
GDSQL.BaseDao.new()
    .use_db("game_config")
    .update("c_hero")
    .set({"hp": 300})
    .where("id = 101")
    .query()

# 删除
GDSQL.BaseDao.new()
    .use_db("game_config")
    .delete_from("c_hero")
    .where("id = 101")
    .query()
```

### 可视化映射图编辑器（Mapper Graph）
拖拽式的映射图编辑器，直观设计数据表之间的关联关系：

- **节点化编辑**：以图节点形式展示数据库表，自由布局
- **一键代码生成**：自动生成完整的项目文件
  - **实体类代码**（`.gd`）：根据表定义自动生成带有 `class_name` 的 GDScript 实体类，包含属性和类型定义
  - **XML 映射文件**（`.xml`）：生成完整的 GBatis 映射文件
  - **Mapper Graph 文件**（`.gdmappergraph`）：保存映射图的节点布局和关系
- **类型推导**：自动将数据库列类型映射为 GDScript 类型
- **关联可视化**：通过连线直观展示表之间的主外键关系
- **增量更新**：当数据库表结构发生变化时，在节点中标注差异，支持选择性同步

### 数据加密
- **AES-256-CBC 加密**：基于 Godot 内置的 `AESContext`
- **DEK 密钥体系**：数据加密密钥 + 用户密码双层保护
- **密钥派生**：HMAC-SHA256 + 随机盐值
- **校验机制**：内置验证码，自动检测密码错误
- **粒度灵活**：支持数据库级别加密和表级别加密
- **编辑器支持**：加密文件在编辑器中需输入密码才能查看

### XML 编辑器
- 内置 XML 编辑器窗口，支持语法高亮
- 查找替换功能
- 树形导航
- 多标签页编辑

### 多语言支持
内置 13 种语言翻译：简体中文、繁体中文、英语、日语、韩语、法语、德语、西班牙语、意大利语、葡萄牙语（巴西）、俄语、波兰语、土耳其语。

---

## 特色与优势

### 对比常见方案

| 特性 | GDSQL | SQLite / GDSQLite | 自定义 Resource 文件 |
|------|-------|-------------------|---------------------|
| 存储格式 | `.cfg` 纯文本 | 二进制数据库文件 | `.tres` / `.res` 文本 |
| SQL 查询 | 完整语法 | ✅ | ❌ |
| 可视化编辑器 | Godot 内嵌 | 需第三方工具 | Godot 内嵌 |
| Excel 风格编辑 | 行内编辑 + 自动填充 | ❌ | ❌ |
| ORM 映射 | ✅ GBatis | ❌ | ❌ |
| 代码生成 | 实体类 + XML 映射 | ❌ | ❌ |
| 运行时 CRUD | 链式 API / GBatis | SQL | ❌ |
| 数据加密 | AES-256-CBC | 需额外实现 | Godot 内建 |
| 版本控制友好 | 纯文本，可 diff | 二进制 | 可 diff |
| 无需外部服务 | ✅ | ✅ | ✅ |
| 跨平台 | Godot 全平台 | 需编译 | Godot 全平台 |

### 核心优势

1. **零外部依赖**——不需要外部数据库引擎、不需要数据库服务器。作为 Godot 插件一键安装，开箱即用。

2. **ConfigFile 数据格式**——所有数据存储在 `.cfg` 文件中，这是 Godot 原生支持的纯文本格式。可以纳入版本控制（git diff 友好），可以用任何文本编辑器直接编辑，可以在 Godot 编辑器外读写。这对于需要频繁调整配置数据的游戏开发流程至关重要。

3. **编辑器与运行时统一 API**——同一个 API 既可以在编辑器中用于开发调试，也可以在发布后的游戏中用于数据读写。不需要维护两套数据访问层。

4. **双模式开发**——既可以使用链式 DAO API（类 JOOQ/JDBI 风格）快速编写数据访问代码，也可以使用 GBatis XML 映射文件实现更复杂的查询和数据映射（类 MyBatis 风格）。

5. **全链路 ORM 体验**——从可视化图编辑器设计数据关系，到自动生成实体类和映射文件，再到运行时 CRUD——覆盖了从数据定义到代码落地的整个流程。开发者只需关注业务逻辑，繁琐的映射代码由工具自动完成。

6. **Excel 级的数据编辑体验**——编辑器内的表格控件支持直接修改数据、拖拽调整列宽、查看长内容，配合智能自动填充，极大提升配置数据的编辑效率。

7. **内置安全机制**——游戏敏感数据（如玩家存档、付费配置）可以直接在插件层面加密，无需额外的加密库。

8. **整体解决方案**——一个插件覆盖了从数据定义、数据管理、数据查询、数据编辑、数据加密到代码生成的全链路需求，无需拼凑多个工具。

---

## 快速开始

1. 将本仓库放到 Godot 项目的 `addons/` 目录下
2. 在 Godot 编辑器 → 项目设置 → 插件中启用 GDSQL
3. 编辑器上方会出现 GDSQL 主屏按钮，点击进入工作台
4. 在工作台中创建数据库和数据表
5. 在代码中使用 `GDSQL.BaseDao` 或 GBatis 进行查询操作

---

## 高级功能：GBatis ORM 映射框架

GBatis 是 GDSQL 内置的 ORM 框架，完整实现了 MyBatis 3 的核心能力。将 SQL 语句定义在 XML 映射文件中，与 GDScript 代码完全分离，适合处理复杂的数据查询和对象映射场景。

GBatis 的 XML 映射文件和实体类 GDScript 脚本支持两种工作方式：

- **手动编写**：高阶用户可以完全自定义 XML 映射文件和实体类代码，精细控制每一个细节
- **可视化生成**：插件内置的 **Mapper Graph 编辑器**支持以拖拽、连线等图形化操作来设计表之间的关联关系，一键生成初始版本：
  - XML 映射文件（`.xml`）：包含完整的 resultMap、动态 SQL 语句等
  - 实体类代码（`.gd`）：带有 `class_name` 的 GDScript 类，包含类型定义和属性注释
  - Mapper Graph 文件（`.gdmappergraph`）：保存节点布局和关系，支持后续增量同步

两种方式可以灵活组合：先用可视化工具快速生成骨架代码，再手动微调细节满足复杂需求。

### 核心能力

- **XML 映射文件**：将 SQL 语句定义在 XML 文件中，与代码完全分离
- **动态 SQL**：`<if>`、`<where>`、`<set>`、`<foreach>`、`<trim>`、`<bind>`
- **结果映射**：`<resultMap>` 支持复杂对象嵌套映射
- **关联与集合**：`<association>` 实现一对一、`<collection>` 实现一对多关联查询
- **鉴别器**：`<discriminator>` 实现基于字段值的多态映射
- **一级 / 二级缓存**：支持缓存配置，提升查询性能
- **自动映射**：NONE 和 PARTIAL 两个级别
- **useGeneratedKeys**：自动回填数据库生成的主键
- **多参数绑定**：支持命名参数和位置参数绑定

### GBatis 使用示例

```xml
<mapper namespace="HeroMapper">
    <resultMap id="heroResult" type="HeroEntity">
        <id property="id" column="id"/>
        <result property="name" column="name"/>
        <result property="hp" column="hp"/>
        <result property="mp" column="mp"/>
    </resultMap>

    <select id="selectHeroesByHp" resultMap="heroResult">
        SELECT * FROM c_hero WHERE hp > #{minHp} ORDER BY hp DESC
    </select>
</mapper>
```

在 GDScript 中创建一个继承 `GBatisMapper` 的类，将 `mapper_xml` 属性指向上述 XML 文件，即可直接调用定义在 XML 中的 SQL 方法。

### 与链式 DAO API 的关系

| 场景 | 推荐方式 | 原因 |
|------|---------|------|
| 简单 CRUD | 链式 DAO API | 代码简洁，无需额外文件 |
| 复杂查询 / 多表关联 | GBatis | SQL 与代码分离，结果映射更强大 |
| 团队协作 | GBatis | DBA 可以维护 XML，程序只关心调用 |
| 快速原型 | 链式 DAO API | 零配置，即写即用 |

---

## 局限性

- **性能天花板**：作为纯 GDScript 实现，GDSQL 不适用于对吞吐量要求极高的实时场景。
- **数据规模**：插件针对游戏配置数据优化（数百到数万条记录），不适合大规模数据仓库或数十万行以上的数据集。
- **并发访问**：基于 ConfigFile 的引擎不支持多线程并发写入，所有数据库操作应在主线程执行。
- **无服务端模式**：GDSQL 是纯本地、基于文件的数据存储，没有网络访问、没有客户端-服务器架构、不支持多用户并发。
- **无参照完整性约束**：外键关系存在于应用层，存储引擎本身不强制约束。
- **索引能力有限**：索引在内存中维护（通过 `ImprovedConfigFile.set_indexed_props()`），没有持久化索引结构。
- **缺乏 DDL 语言支持**：目前数据定义操作（创建表、修改列等）仅通过可视化界面进行，不支持 `CREATE TABLE`、`ALTER TABLE` 等 DDL 语句。

---

## 未来计划

- **性能优化路线图**：识别热点路径并持续优化，包括 GDScript 层优化和关键路径的 GDExtension 原生模块方案
- **更多 SQL 语法**：窗口函数、CTE（通用表表达式）、完整 JOIN 支持（INNER、RIGHT、FULL）
- **DDL 语言支持**：增加 `CREATE TABLE`、`ALTER TABLE`、`DROP TABLE` 等 DDL 语句的支持
- **查询计划优化**：更好的执行顺序、LEFT JOIN 谓词下推
- **更多易用性功能**：简化日常操作流程，降低使用门槛
- **质量改进（QOL）**：更好的错误提示、撤销 / 重做、批量操作、快捷键增强
- **全面文档站点**：独立的 API 参考、教程和实际使用示例
- **测试基础设施**：扩大的单元测试覆盖率和完整的查询生命周期集成测试

---

## 许可

[MIT License](LICENSE)
