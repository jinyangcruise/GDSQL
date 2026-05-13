<div align="center">

# GDSQL

**Database SQL Workbench Plugin for Godot Engine**

**English** | [简体中文](README_zh.md)

[![Godot](https://img.shields.io/badge/Godot-4.x-478CBF?logo=godot-engine&logoColor=white)](https://godotengine.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Pure GDScript](https://img.shields.io/badge/100%25-GDScript-3b82f6)]()

A database SQL workbench plugin for Godot Engine built on top of the `ConfigFile` system. It provides a visual database management interface, Excel-like data editing, a full SQL query engine, a MyBatis-style ORM mapping framework (GBatis), and AES-256-CBC data encryption. **Pure GDScript, zero external dependencies, no database server required.**

</div>

---

## Features

### SQL Query Engine
- **Full SQL syntax**: SELECT / INSERT / UPDATE / DELETE / REPLACE
- **Conditional queries**: WHERE, AND, OR, IN, NOT IN, BETWEEN, LIKE, IS NULL
- **Sorting & grouping**: ORDER BY, GROUP BY, HAVING
- **Pagination**: LIMIT, OFFSET
- **Joins**: LEFT JOIN with chainable multi-table support
- **Set operations**: UNION ALL
- **Subqueries**: Correlated and non-correlated
- **Aggregate functions**: COUNT, SUM, AVG, MIN, MAX, GROUP_CONCAT, and more
- **Expression evaluation**: SQL-compatible null semantics, operators, function calls, type conversion
- **LRU cache**: Auto-caches the last 1024 parsed SQL statements

### Visual Database Workbench
Available as a dedicated main screen in the Godot Editor:

- **Database tree browser**: Navigate all databases and tables in a tree view
- **Data table viewer**: Browse and edit data in an Excel-like grid
- **Inline editing**: Modify data directly in table cells with instant effect
- **Drag-to-resize columns**: Freely adjust column widths
- **Table structure editor**: View and modify column definitions, types, defaults, and comments
- **Schema management**: Visually create / delete / edit databases and tables
- **Data import/export**: CSV, JSON, and CFG formats
- **Diff view**: Compare table content with highlighted additions, deletions, and changes
- **SQL query editor**: Write and execute SQL with automatic query history
- **Export query results**: Export results as CSV, JSON, or CFG

### Smart Auto-Fill
- **Least-squares fitting**: Predicts and fills subsequent data based on existing samples
- **Multi-type support**: Numbers, strings (with numeric placeholders), Vector2/3/4, Vector2i/3i/4i, Resource paths
- **Pattern recognition**: Detects numbering patterns (e.g. `"name_001"`, `"name_002"`) and fills accordingly

### Fluent DAO API
Complete database operations through GDScript method chaining — no XML required:

```gdscript
# Select
var result = GDSQL.BaseDao.new()
    .use_db("game_config")
    .select("id", "name", "hp", "mp")
    .from("c_hero")
    .where("hp > 100 AND mp >= 50")
    .order_by("hp")
    .limit(10)
    .query()

# Insert
GDSQL.BaseDao.new()
    .use_db("game_config")
    .insert_into("c_hero")
    .values({"id": 101, "name": "NewHero", "hp": 200})
    .query()

# Update
GDSQL.BaseDao.new()
    .use_db("game_config")
    .update("c_hero")
    .set({"hp": 300})
    .where("id = 101")
    .query()

# Delete
GDSQL.BaseDao.new()
    .use_db("game_config")
    .delete_from("c_hero")
    .where("id = 101")
    .query()
```

### Mapper Graph Visual Editor
A drag-and-drop graph editor for designing table relationships:

- **Node-based editing**: Display tables as graph nodes with free-form layout
- **One-click code generation**:
  - **Entity class** (`.gd`): Auto-generated `class_name` entity with typed properties
  - **XML mapping file** (`.xml`): Complete GBatis mapping
  - **Mapper Graph file** (`.gdmappergraph`): Persisted layout and relationships
- **Type inference**: Database column types → GDScript types
- **Relationship visualization**: Lines show foreign-key connections
- **Incremental sync**: Detects schema changes and highlights differences

### Data Encryption
- **AES-256-CBC**: Built on Godot's native `AESContext`
- **DEK hierarchy**: Data encryption key + user password dual-layer protection
- **Key derivation**: HMAC-SHA256 with random salt
- **Verification**: Built-in verify code detects wrong passwords
- **Flexible granularity**: Database-level and table-level encryption
- **Editor support**: Encrypted files require a password to view in-editor

### XML Editor
- Built-in XML editor with syntax highlighting
- Find and replace
- Tree view navigation and multi-tab editing

### Internationalization
13 languages: Simplified Chinese, Traditional Chinese, English, Japanese, Korean, French, German, Spanish, Italian, Portuguese (BR), Russian, Polish, Turkish.

---

## Highlights

### Comparison

| Feature | GDSQL | SQLite / GDSQLite | Custom Resource |
|---------|-------|-------------------|-----------------|
| Storage | `.cfg` plain text | Binary | `.tres` / `.res` |
| SQL queries | Full syntax | ✅ | ❌ |
| Visual editor | Built into Godot | Third-party | Built into Godot |
| Excel-like editing | Inline + auto-fill | ❌ | ❌ |
| ORM mapping | ✅ GBatis | ❌ | ❌ |
| Code generation | Entity + XML mapping | ❌ | ❌ |
| Runtime CRUD | Fluent API / GBatis | SQL | ❌ |
| Encryption | AES-256-CBC | Manual | Godot built-in |
| VCS friendly | Plain text, diffable | Binary | Diffable |
| No external services | ✅ | ✅ | ✅ |
| Cross-platform | Godot everywhere | Needs compilation | Godot everywhere |

### Key Advantages

1. **Zero external dependencies** — No database engine, no database server, no additional runtime. Install as a plugin and it works.

2. **ConfigFile-based storage** — All data lives in `.cfg` plain text files, Godot's native format. Version control friendly (git diff), editable in any text editor, accessible outside the Godot editor.

3. **Unified editor & runtime API** — The same API works in-editor for development and in the exported game for runtime access. No need to maintain two data access layers.

4. **Dual development modes** — Use the fluent DAO API for quick data access, or GBatis XML mapping files for complex queries and result mapping.

5. **End-to-end ORM pipeline** — From visual graph editor to auto-generated entity classes and mapping files to runtime CRUD. Developers focus on business logic while the tool handles the boilerplate.

6. **Excel-grade data editing** — Inline cell editing, draggable columns, long-content viewing, and smart auto-fill dramatically improve editing efficiency.

7. **Built-in security** — Sensitive game data can be encrypted directly at the plugin level.

8. **All-in-one solution** — A single plugin covers data definition, management, querying, editing, encryption, and code generation.

---

## Quick Start

1. Place this repository into your Godot project's `addons/` directory
2. Enable GDSQL in Godot Editor → Project Settings → Plugins
3. Click the GDSQL main screen button at the top of the editor
4. Create databases and tables in the workbench
5. Use `GDSQL.BaseDao` or GBatis for runtime queries

---

## Advanced: GBatis ORM Framework

GBatis is the built-in ORM framework, fully implementing MyBatis 3 capabilities. SQL statements live in XML mapping files, completely separate from GDScript code — ideal for complex queries and object mapping.

GBatis supports two working modes:

- **Manual authoring**: Advanced users can fully customize XML and entity code for fine-grained control
- **Visual generation**: The built-in **Mapper Graph editor** lets you design relationships through drag-and-drop, then generate initial versions with one click:
  - XML mapping files (`.xml`): Complete resultMap and dynamic SQL
  - Entity class code (`.gd`): `class_name` GDScript class with typed properties
  - Mapper Graph file (`.gdmappergraph`): Persisted node layout for incremental updates

The two approaches can be combined: quickly scaffold with the visual editor, then manually fine-tune.

### Core Capabilities

- **XML mapping files**: SQL in XML, decoupled from code
- **Dynamic SQL**: `<if>`, `<where>`, `<set>`, `<foreach>`, `<trim>`, `<bind>`
- **Result mapping**: `<resultMap>` for complex nested object mapping
- **Associations & collections**: One-to-one and one-to-many via `<association>` / `<collection>`
- **Discriminator**: Polymorphic mapping based on field values
- **L1 / L2 caching**: Configurable cache for query performance
- **Auto-mapping**: NONE and PARTIAL levels
- **useGeneratedKeys**: Auto-populate generated primary keys
- **Multi-parameter binding**: Named and positional parameter support

### GBatis Example

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

Create a class extending `GBatisMapper` and point its `mapper_xml` property to the XML file above. The SQL methods become directly callable.

### Fluent DAO vs. GBatis

| Scenario | Recommended | Why |
|----------|------------|-----|
| Simple CRUD | Fluent DAO | Concise, no extra files |
| Complex queries / joins | GBatis | SQL-code separation, powerful mapping |
| Team collaboration | GBatis | DBA handles XML, devs call methods |
| Rapid prototyping | Fluent DAO | Zero config, write and use |

---

## Limitations

- **Performance ceiling**: As a pure GDScript implementation, GDSQL is not designed for real-time high-throughput scenarios.
- **Data volume**: Optimized for game configuration data (hundreds to tens of thousands of records), not for data warehouses or datasets exceeding hundreds of thousands of rows.
- **Concurrent access**: The ConfigFile-based engine does not support multi-threaded concurrent writes. All operations should run on the main thread.
- **No server mode**: Local-only, file-based data store. No network access, no client-server architecture, no multi-user concurrency.
- **No referential integrity**: Foreign key relationships exist at the application level; the storage engine itself does not enforce constraints.
- **Limited indexing**: Indexes are maintained in memory via `ImprovedConfigFile.set_indexed_props()` — no persistent index structure.
- **No DDL statements**: Data definition operations (creating tables, modifying columns) are currently only available through the visual interface, not through `CREATE TABLE` or `ALTER TABLE` statements.

---

## Future Plans

- **Performance roadmap**: Identify hot paths and optimize — both GDScript-level and via GDExtension for critical sections
- **Extended SQL syntax**: Window functions, CTEs (Common Table Expressions), full JOIN support (INNER, RIGHT, FULL)
- **DDL language support**: `CREATE TABLE`, `ALTER TABLE`, `DROP TABLE` statements
- **Query planner optimization**: Better execution order, LEFT JOIN predicate push-down
- **More ease-of-use features**: Simplify common workflows, lower the learning curve
- **Quality-of-life improvements**: Better error messages, undo/redo, batch operations, enhanced keyboard shortcuts
- **Comprehensive documentation site**: Dedicated API reference, tutorials, and real-world examples
- **Testing infrastructure**: Expanded unit test coverage and integration tests for the full query lifecycle

---

## License

[MIT License](LICENSE)
