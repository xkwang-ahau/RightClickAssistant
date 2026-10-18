# 右键助手（RightClickAssistant）

一个 macOS 菜单栏小工具 + Finder 扩展：在 Finder 里右键即可新建 Word / PowerPoint / Excel 空白文档，或把文件移动到指定文件夹。所有操作默认**绝不覆盖**已有文件。

## 功能

- **右键新建文档**：在任意普通文件夹空白处右键 →「右键助手」→ 新建 Word / PowerPoint / Excel 文档。后台直接创建，不弹主界面；同名文件自动编号为「新建 Word 文档 (2).docx」。
- **右键移动文件**：单个普通文件右键 →「移动此文件…」，选择目的地后后台移动。
- **同名冲突处理**：目的地已有同名文件时提供「保留两者 / 替换 / 取消」，默认保留两者，只有明确选择「替换」才会覆盖。
- **菜单栏面板**：查看 Finder 扩展启用状态、管理文件夹授权、查看最近一次操作结果并在 Finder 中显示。
- **授权根复用**：保存一个文件夹授权根（安全书签），其所有子目录右键创建都不再重复授权，重启应用后恢复。
- **全卷范围**：菜单覆盖启动磁盘与所有已挂载卷，插拔磁盘后自动刷新。

## 系统要求

- macOS 14.0 或更高版本
- Xcode 15+（Swift 5）
- 无第三方运行时依赖

## 项目结构

```text
rightchick/
├── rightchick/              主 App（SwiftUI + AppKit，菜单栏工具）
│   ├── MyApp.swift          菜单栏入口
│   ├── AppDelegate.swift    状态所有者与扩展管理
│   ├── ContentView.swift    设置面板
│   ├── Models/              文档类型、创建与移动状态、目录偏好
│   ├── Features/Workspace/  WorkspaceModel（界面状态唯一来源）
│   ├── Services/            文件操作、选择器、书签存储、Finder 集成
│   └── Resources/Templates/ 三种空白 OOXML 模板
├── FinderExtension/         Finder Sync 扩展（右键菜单入口）
├── Shared/                  主 App 与扩展共享的请求传递类型
├── rightchickTests/         单元测试
├── scripts/                 模板生成与验证脚本
└── docs/                    架构说明与使用记录
```

整体是轻量 MVVM：`ContentView → WorkspaceModel → FileOperationService`。真正的文件 IO 由独立 actor 承担，安全书签由 `FolderBookmarkStore` 管理；Finder 扩展只负责收集请求并通过自定义 URL 交给主 App，自己不写文件。

## 构建与运行

1. 用 Xcode 打开 `rightchick.xcodeproj`。
2. 选择 `rightchick` scheme 与 `My Mac`，按 `⌘R` 运行。Finder 扩展会作为内嵌 appex 自动构建。
3. 首次运行时，在菜单栏面板点击「管理 Finder 扩展…」，在系统设置中启用「右键助手 Finder 菜单」。
4. 在 Finder 中打开任意普通文件夹，右键即可看到「右键助手」。

> 首次访问桌面、文稿、下载或外接盘时，macOS 会弹出一次「文件与文件夹」授权提示，允许后不再打扰。系统保护目录和只读磁盘仍不可写。

## 测试

在 Xcode 中按 `⌘U`。`rightchickTests` 共 97 个测试方法，覆盖文档创建、无覆盖移动、冲突处理、安全书签往返、菜单请求解析与并发互斥。测试只使用临时目录，不会触碰用户已有文档。

```sh
xcodebuild test -project rightchick.xcodeproj -scheme rightchick -destination 'platform=macOS'
```

## Office 空白模板

`rightchick/Resources/Templates/` 下的 `.docx / .pptx / .xlsx` 由脚本生成并校验，App 运行时只复制资源：

```sh
python3 scripts/generate_office_templates.py   # 需要 python-docx / python-pptx / openpyxl
python3 scripts/verify_office_templates.py
```

生成库（MIT 许可）仅在构建模板时使用，不会打包进 App；相关版权说明见 `rightchick/Resources/OfficeTemplateLicenses.txt`。

## 已知限制

- 目前只支持同卷普通文件的移动；跨卷、目录与符号链接不支持。
- 移动使用 `renamex_np` + `RENAME_EXCL` 实现原子无覆盖，不做复制后删除。
- 使用临时开发签名（`devplaceholder` 前缀 Bundle ID），正式分发需替换签名与 Bundle ID。
- 当前尚未设计 App 图标。

## 仓库说明

本仓库只包含应用代码、工程文件、测试与文档。AI agent 脚手架（`.agent/`、`.codex/`、`AGENTS.md`）仅保留在本地，已通过 `.gitignore` 排除。

## 第三方许可

Office 模板由 python-docx、python-pptx、openpyxl 生成，三者均为 MIT 许可。完整声明见 `rightchick/Resources/OfficeTemplateLicenses.txt`。
