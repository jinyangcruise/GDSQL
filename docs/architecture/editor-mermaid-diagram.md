flowchart TD

classDef integration fill:#EDE9FE,stroke:#7C3AED,stroke-width:2px,color:#2E1065;
classDef action fill:#F3E8FF,stroke:#8B5CF6,stroke-width:2px,color:#3B0764;
classDef surface fill:#E8F1FF,stroke:#3B82F6,stroke-width:2px,color:#172554;
classDef coordination fill:#FFF7D6,stroke:#D97706,stroke-width:2px,color:#451A03;
classDef graphs fill:#FCE7F3,stroke:#DB2777,stroke-width:2px,color:#500724;
classDef runtime fill:#DCFCE7,stroke:#16A34A,stroke-width:2px,color:#052E16;
classDef feedback fill:#F1F5F9,stroke:#475569,stroke-width:2px,color:#0F172A;

Integration("`**Editor Integration**

-
*Purpose:* Own GDSQL's Godot editor lifecycle
*Surfaces:* Database dock, workspace, activity panel
*Connects:* Shared editor actions and coordinators`")

Actions("`**Action Coordination**

-
*Purpose:* Expose stable actions across editor locations
*Editor hub:* Discovers and routes actions
*Context hubs:* Own availability and behavior`")

Dock("`**Database Dock**

-
*Purpose:* Navigate registrations, tables and columns
*Uses:* Lightweight inspection metadata
*Delegates:* Discovery, refresh and selection`")

Workspace("`**Central Workspace**

-
*Purpose:* Host query graphs and database task pages
*Owns:* Active documents and focused context
*Uses:* Opened workbench sessions`")

ModelAssistant("`**Model Assistant**

-
*Purpose:* Preview generated schema bindings and user-owned models
*Input:* Selected catalog table and logical role
*Inspection:* Typed compatibility diagnostics and relationship target roles
*Safety:* One-way generation; user scripts are never replaced`")

SaveSlots("`**Save Slots**

-
*Purpose:* Discover and select direct-content save databases
*Boundary:* user://gdsql/saves direct children plus active custom root
*Safety:* Creation and role binding only; no implicit durable deletion`")

Activity("`**Activity Bottom Panel**

-
*Purpose:* Present operation history and feedback
*Displays:* Status, diagnostics and duration`")

Workbench("`**Workbench**

-
*Purpose:* Coordinate known database registrations
*API:* load(), discover_root(), select_registration()
*Rows:* Remain unloaded during discovery`")

Session("`**Workbench Session**

-
*Purpose:* Coordinate one opened database
*API:* select_table(), load_rows(), preview and apply changes
*State:* Catalog, selected table and bounded row page`")

Graphs("`**Query Graph Frontend**

-
*Purpose:* Author a typed visual query
*Flow:* QueryGraph → GraphQueryCompiler
*Produces:* QuerySpec`")

Runtime("`**Runtime Boundary**

-
*Purpose:* Execute canonical operations
*Entry points:* Database, registry and catalog administration
*Returns:* Values and structured diagnostics`")

Integration -->|"register surfaces"| Dock
Integration -->|"register surfaces"| Workspace
Integration -->|"register surface"| Activity
Integration -->|"compose"| Actions

Actions -->|"route dock actions"| Dock
Actions -->|"route active-document actions"| Workspace

Dock -->|"load · discover · select"| Workbench
Workbench -->|"open registration"| Session
Workspace -->|"table and catalog tasks"| Session
Workspace -->|"edit graph document"| Graphs
Workspace -->|"preview model binding"| ModelAssistant
Workspace -->|"manage active save role"| SaveSlots
SaveSlots -->|"discover · bind · open"| Workbench

Graphs -->|"compile(graph) · execute(query)"| Runtime
Session -->|"catalog and canonical query operations"| Runtime
Runtime -->|"results · diagnostics"| Activity

class Integration integration;
class Actions action;
class Dock,Workspace,ModelAssistant,SaveSlots surface;
class Workbench,Session coordination;
class Graphs graphs;
class Runtime runtime;
class Activity feedback;
