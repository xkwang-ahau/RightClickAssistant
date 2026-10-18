# RightClickAssistant：项目结构与开发说明

> **当前交互（2026-10-16）**：应用已移除沙盒、改用“完全磁盘访问”，并改为菜单栏工具（无 Dock、不自动弹窗）。Finder 右键新建在后台直接创建（无需逐目录授权），移动在后台选择目的地后执行。主界面为菜单栏设置面板（扩展状态、完全磁盘访问、最近结果、退出）。下文早期 M1–M4 手动表单操作作为历史开发记录，当前使用以 [Finder 菜单说明](finder-menu.md) 为准。最近 90 项测试通过，详见 `.agent/plans/full-disk-background.md`。

## 1. 当前项目结构

最初的项目仅有 MyApp.swift、ContentView.swift、Assets.xcassets 和 RightClickAssistant.xcodeproj，是显示 Hello world 的多平台模板，没有文件服务或 Finder 扩展。

M1 / M2 / M3 / M4 建立的小规模结构如下：

```text
RightClickAssistant/
├── AGENTS.md                        开发约束
├── .agent/PLANS.md                   计划格式
├── .agent/plans/right-click-foundation.md
├── .agent/plans/folder-persistence.md  M4 实施与验证记录
├── docs/architecture.md             本说明
├── RightClickAssistant.xcodeproj/
│   ├── project.pbxproj               Target、平台、权限与构建设置
│   └── xcshareddata/xcschemes/        包含测试的共享 Scheme
├── RightClickAssistantTests/                 文件安全与状态测试
├── scripts/                        模板生成与验证脚本
└── RightClickAssistant/
    ├── MyApp.swift                  启动入口与状态所有者
    ├── ContentView.swift            主窗口
    ├── Models/DocumentType.swift    Office 文档类型
    ├── Models/DocumentCreation.swift 名称规则、错误和创建状态
    ├── Models/FileMovement.swift    移动错误和状态
    ├── Models/FolderPreference.swift 保存位置、恢复结果和书签错误
    ├── Features/Workspace/WorkspaceModel.swift
    ├── Services/FolderPicker.swift  系统目录选择
    ├── Services/FilePicker.swift    系统文件选择
    ├── Services/FileOperationService.swift 文件创建与移动
    ├── Services/ExclusiveFileMove.swift 无覆盖重命名
    ├── Services/FolderBookmarkStore.swift 保存与解析安全书签
    ├── RightClickAssistant.entitlements      应用级安全书签权限
    ├── Resources/                   Office 空白模板及许可说明
    └── Assets.xcassets/             颜色与图像资源
```

当前有 RightClickAssistant 应用 Target 和 RightClickAssistantTests 单元测试 Target。Xcode 的目录同步分组会自动纳入对应目录中的新增 Swift 文件。

M5 增加 FinderExtension Target，自动嵌入主 App 的 `Contents/PlugIns`；新增 `Shared/FinderRequest.swift` 同时编译到 App 与扩展。2026-10-16 已扩展到启动磁盘和所有挂载卷，新增 `AuthorizedCreationLocation.swift` 管理父目录授权与子目录目标。启用范围、体验步骤及本机验证见 [Finder 右键菜单试用](finder-menu.md)。

## 2. 每个主要文件做什么

| 文件 | 职责 |
| --- | --- |
| MyApp.swift | `@main` 标记启动入口；创建单个窗口，持有 WorkspaceModel 并传给界面 |
| ContentView.swift | 紧凑设置窗口，显示扩展状态、真实授权根与最近菜单结果 |
| DocumentType.swift | 用 enum 表示 Word / PowerPoint / Excel，集中保存显示名称和扩展名 |
| WorkspaceModel.swift | 保存用户输入、目录和源文件，管理创建/移动任务与结果；是这些状态的唯一真实来源 |
| FolderPicker.swift | 使用 AppKit 的 NSOpenPanel 选择目录，取消时返回 nil |
| FilePicker.swift | 使用 NSOpenPanel 选择单个文件，取消时保留此前选择 |
| DocumentCreation.swift | 预览和创建共用的名称规则、用户错误、创建状态 |
| FileMovement.swift | 移动状态、中文错误；保留原文件名，不使用新建文档的名称规则 |
| FileOperationService.swift | 独立 actor，处理本次安全访问、模板复制、源/目标校验和移动错误 |
| ExclusiveFileMove.swift | 用系统的 renamex_np + RENAME_EXCL 完成同卷无覆盖移动；不复制后删除 |
| FolderPreference.swift | 区分创建位置与移动目的地，定义恢复结果和中文错误 |
| FolderBookmarkStore.swift | 用两个版本化 UserDefaults 键保存安全书签；解析、检查目录、刷新过期书签、清除配置 |
| RightClickAssistant.entitlements | 增加 app-scope bookmarks 权限；沙盒与用户选择读写权限仍由构建设置生成 |
| RightClickAssistantTests | 用真实临时目录验证文件安全，用可控假服务验证状态与并发请求 |
| Assets.xcassets | 资源目录，目前只有 AccentColor，尚未设计 App 图标 |
| project.pbxproj | 记录 macOS Target、最低版本 14.0、沙盒与用户选择文件读写权限 |

## 3. 推荐架构

采用简单的 SwiftUI 界面 + 可观察的功能模型 + 专注服务，类似轻量 MVVM。MVVM 在这里只意味着“显示、状态、系统操作各有职责”，没有必要引入很多抽象层。

```text
ContentView → WorkspaceModel → FolderPicker / FilePicker
                     ↓
              FileOperationService → Office 模板 / 文件系统
                     ↓
               ExclusiveFileMove → Darwin 重命名 API

WorkspaceModel → FolderBookmarkStore → UserDefaults（两份 Data）
                         ↓
               SecurityScopedBookmarkAccess → Foundation 安全书签 API
```

Finder 菜单作为另一个入口复用文件操作规则。主 App 的窗口菜单并不会自动变成 Finder 菜单。M5 已实现 Finder Sync 入口，当前注册根目录与所有挂载卷：扩展通过自定义 URL 打开其包含 App；新建请求复用已有授权根及其子目录，或经系统选择窗口获取授权，随后自动创建，重名编号。根的安全访问在整个创建期间保持。移动请求准备源文件并由用户确认目的地后执行。扩展不直接写文件，不复用 App 内存或 app-scope 书签。菜单范围不等于无限写权限；只读卷和系统保护目录仍按实际 IO 返回错误。

参考：[Apple Finder Sync 指南](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html)。

## 4. 数据和状态怎么流动

App 持有模型 → 界面显示模型的值 → 输入框通过绑定修改名称、类型 → 模型变化自动刷新预览。

点击目录选择按钮 → 模型调用 FolderPicker → 系统窗口返回目录 URL 或 nil → 模型更新对应目录。取消时保留此前选择。两个目录互相独立。

点击“创建文档” → 模型校验并固定本次名称、类型、目录 → 状态变为 creating → await 文件服务复制模板 → 状态变为 created(URL) 或 failed(中文错误) → 界面自动更新。执行期间禁用重复操作。窗口关闭时取消待执行任务；复制已完成时按真实成功结果反馈。

点击“移动文件” → 模型固定本次源文件和目的地 → 状态变为 moving → await 服务验证普通文件并重命名 → 状态变为 moved(URL) 或 failed(中文错误)。成功后清空源选择，保留目的地；失败保留源选择以便重试。取消文件/目录选择保留当前值，重新选择成功后清除旧的移动提示。

isBusy 根据 creating / moving 计算，避免同时运行创建与移动。它是派生状态，不额外保存一份 Bool。文件操作前检查取消；操作已经完成时反馈真实成功，取消不会把文件自动移回去。

预览文件名是“派生状态”：根据输入名称及扩展名计算，不另外保存。M4 将两个目录分别保存成安全书签，单独保存路径无法保证下次启动仍有权限。源文件、名称、类型和操作结果不持久化。

App 显式注入 FolderBookmarkStore → 模型启动时恢复两个位置 → 解析时不弹系统窗口、不自动挂载磁盘 → 临时开启安全访问并检查目录 → 必要时刷新过期书签 → 结束本次访问。之后创建和移动仍由文件服务按每次操作管理访问。

恢复失败时该位置保持未选择并显示“请重新选择”，不影响另一位置。新选择保存失败时仍可在本次使用，但删除该位置的旧书签并提示“仅本次可用”。取消选择不改变配置；“清除”仅清除对应偏好与当前目录，不删除目录里的文件，文件操作执行期间不能清除。

真正的文件 IO 由文件服务处理，成功/失败再回到模型。`View.body` 仅描述界面，不能每次刷新时创建或移动文件。

参考：[Apple 沙盒文件访问说明](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)。

## 5. 第一阶段实现什么

M1 已实现管理窗口和目录选择。M2 已实现真正创建三种 Office 文档、非法名称提示、同名保护、成功反馈和在 Finder 中显示。M3 已实现单文件移动。M4 已实现常用目录与安全书签持久化，并通过自动测试；真实外部目录重启授权仍待人工验收。

M2 的创建使用合法空白模板，复制后是可被支持 OOXML 的软件读取的文档。M3 的范围是：

- 通过系统选择窗口选择源文件并移动，第一版先支持单个文件。
- 同名冲突停止并提示，保留已有文件；权限不足和源文件消失有清楚的错误反馈。
- 支持同一文件系统内的普通文件，保留名称、内容与权限。目录、符号链接源、跨卷移动暂不支持；云盘和第三方文件提供者未经验证。

移动使用系统无覆盖重命名，因为 Foundation 的 moveItem 跨卷时会复制后删除，这需要另一套失败恢复设计。[Apple FileManager 文档](https://developer.apple.com/documentation/foundation/filemanager/moveitem(atpath:topath:))、[Apple rename 手册](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/rename.2)。

M5 已进入本机试用：菜单扩展构建、注册、选用和进程启动通过，下一步确认真实 Finder 显示与点选，然后推进自定义目录范围。完整里程碑和边界见 ExecPlan。

## 6. 需要创建和修改哪些文件

M1 修改原有 MyApp.swift、ContentView.swift、project.pbxproj，新增 DocumentType.swift、WorkspaceModel.swift、FolderPicker.swift、ExecPlan 和本说明。

M2 修改入口、界面、模型、类型和选择器，新增 FileOperationService.swift、DocumentCreation.swift、Resources/Templates、许可说明、生成/验证脚本、XCTest 文件与 Target，以及共享测试 Scheme。Finder 入口通过技术验证后再新增对应 Target 与配置。

M3 新增 FileMovement.swift、FilePicker.swift、ExclusiveFileMove.swift、FileMovementServiceTests.swift、FileMovementModelTests.swift；修改 MyApp.swift、ContentView.swift、WorkspaceModel.swift、FileOperationService.swift 和 WorkspaceModelTests.swift 的初始化，以及 ExecPlan 和本说明。没有新增依赖、Target 或权限。

M4 新增 FolderPreference.swift、FolderBookmarkStore.swift、RightClickAssistant.entitlements、FolderBookmarkStoreTests.swift 和 FolderPersistenceModelTests.swift；修改入口、模型、界面、项目签名设置和移动模型互斥测试。新计划位于 `.agent/plans/folder-persistence.md`，不新增依赖或 Target。

暂时不创建数据库、登录项、后台进程或第三方依赖。

## 7. 初学者需要理解哪些概念

| 概念 | 在本项目解决什么问题 |
| --- | --- |
| let / var | let 是不可改的引用或值，var 是需要变化的值；服务引用用 let，用户输入用 var |
| struct / class | View 使用 struct；共享的可观察状态模型使用 class，让界面持有同一个模型实例 |
| enum | 文档类型只能从三种合法情况中选择 |
| Optional、nil、if let | 尚未选择目录时 URL 为 nil；if let 只在确实有选择时更新状态 |
| @State | App 保持模型实例的生命周期，不在每次界面刷新时新建模型 |
| @Observable | 模型的属性变化后，让读取它们的 SwiftUI 界面自动更新 |
| @Bindable | 输入框和 Picker 可直接修改模型的名称与文档类型；`$model.documentName` 是双向连接 |
| @Binding | 子界面借用可修改状态时使用，本轮没有必要额外添加 |
| @MainActor | 模型与目录选择窗口在主线程操作，保持界面状态更新安全 |
| actor / nonisolated | actor 按顺序处理文件 IO；纯文档类型和名称规则用 nonisolated 表明不依赖界面主线程 |
| async / await | 在等待文件服务时让出主线程，界面可以响应；await 不等于创建新线程 |
| protocol / any | 定义服务必须提供的能力；模型接收任意符合协议的实现，测试可用可控假服务替换 |
| enum 的关联值 | created(URL) 带有成功文件，failed(String) 带有错误；避免多个 Bool 表示互相矛盾的状态 |
| throws / do-catch | 服务把错误抛出，模型转成可以在界面显示的失败状态 |
| defer | 退出服务方法时归还本次临时文件访问权，成功或抛出错误都会执行 |
| Task / 取消 | 保存一次操作的任务句柄；关闭窗口时发出取消请求，服务在执行前检查它 |
| private(set) | 界面可读取源文件和结果，只有模型内部能改变它们，避免绕过操作规则 |
| 依赖注入 | MyApp 创建 FolderPicker，再通过初始化参数传给模型，依赖关系看得见 |
| SwiftUI / AppKit | SwiftUI 描述管理界面；AppKit 提供原生目录选择窗口 |
| URL / Sandbox / 安全书签 | 分别表示位置、限制访问范围、保存可恢复的目录授权 |
| Target / Scheme | Target 决定构建什么产品；Scheme 决定运行或构建哪些 Target 和配置 |

## 如何运行和检查本轮结果

在 Xcode 打开 RightClickAssistant.xcodeproj，选择 RightClickAssistant scheme、My Mac，点击 Run（Command-R）。

1. 检查出现“右键助手”窗口。
2. 输入“会议记录”，切换 Word / PowerPoint / Excel，查看 `.docx/.pptx/.xlsx` 名称预览。
3. 分别选择创建位置和移动目的地，检查它们独立更新。
4. 已经选好目录后点“更换”，再取消，检查原选择保留。
5. 点击“创建文档”，检查成功反馈及“在 Finder 中显示”，再创建同名文件，检查停止并提示，原文件保持不变。
6. 输入 `../报告` 或空名称，检查提示错误并禁用创建。输入 `报告.docx` 再切换 Excel，预览应为 `报告.xlsx`。
7. 用一个测试文件选择“源文件”，选择同一磁盘中的其他文件夹，点“移动文件”。检查原路径消失、目标内容不变、源选择清空、结果可以在 Finder 中显示。
8. 在目的地放一个同名测试文件后再次移动，检查失败提示、源文件及目的地内容均保留。选择源所在目录应提示无需移动；更换/取消选择时检查状态。
9. 选择两个不同目录后退出，再启动，检查两个目录恢复，源文件未恢复；使用恢复的创建位置创建新文档，并重新选择一个测试源文件验证移动。
10. 清除一个位置，检查另一个仍保留；退出再启动，已清除位置应保持未选择。清除设置不会删除文件夹或文件。
11. 保存一个专用空测试目录，退出 App 后删除该目录，再启动，检查该位置提示重新选择；取消选择应保留提示，重新选择有效目录应清除提示。
12. Finder 桌面范围右键菜单启用与点选步骤见 `docs/finder-menu.md`。

在 Xcode 按 Command-U 可运行单元测试。测试先创建临时目录和测试输入，再执行操作，最后检查文件内容或错误；不使用用户已有文档。

## 本轮验证结果（2026-10-06）

- M2 Debug 签名构建及 22 个 XCTest 全部通过，0 失败，0 跳过，无 Swift 源码编译警告。
- 已检查源码风格、项目配置格式、修改差异以及生成的沙盒读写权限。
- 三种模板的结构、实际 Bundle 打包、创建输出字节一致性及 LibreOffice 实际读取/转换检查通过。
- 窗口自动化服务中断，尚未完成真实目录选择与按钮流程、布局及 Microsoft Office 打开检查。请按上面的步骤在 Xcode 中人工检查；模型单测通过不能代替真实 NSOpenPanel 授权验证。

M3 独立 Debug 沙盒 App 编译成功；45 个 XCTest 全部通过（22 项创建回归、14 项移动文件测试、9 项移动模型测试），0 失败、0 跳过，无 Swift 源码编译警告。检查了内容/权限保持、各类已有目标保护、只读目录、竞争请求、取消时机、互斥和重试。跨卷错误用系统调用边界注入测试，未操作真实外接盘或云盘。

本轮真实窗口检查仍返回 `Sky Computer Use native pipe closed before response`，没有完成 NSOpenPanel 外部目录授权、实际按钮流程与 Finder 显示验证。当前不能把自动测试通过等同于这些 UI 流程已通过。详细结果和日志路径见 ExecPlan。

## M4 验证结果（2026-10-12，America/Los_Angeles）

- Debug 本地临时签名构建通过；检查签名包含 Sandbox、用户选择读写、app-scope bookmarks 和 Debug 调试权限。
- 最终 60 项 XCTest 通过，0 失败、0 跳过、无 runtimeWarnings：原有 45 项回归、10 项书签服务测试、5 项目录状态测试。
- 真实临时目录验证安全书签往返、删除后失效、普通文件拒绝、恢复后的三个 Office 文件创建及移动。隔离 UserDefaults suite 与系统边界替身覆盖损坏数据、独立清除、stale 更新、更新失败、保存失败和安全访问配对；已有互斥测试增加操作期间禁止清除的断言。
- 未出现 Swift 源码编译警告；项目与 entitlements 格式检查通过，已按原有四空格和补丁逐文件复核修改。
- 测试结果：`/var/folders/2m/wsdtb63j6hl_24pwvwnbjp980000gn/T/opencode/rightchick-m4-final-tests.xcresult`。
- 已在独立 DerivedData 构建普通 App，产物：`/var/folders/2m/wsdtb63j6hl_24pwvwnbjp980000gn/T/opencode/rightchick-m4-app-derived/Build/Products/Debug/右键助手.app`，无构建警告，签名权限复核通过。
- 本会话没有桌面操作工具。测试宿主中的临时目录验证不等同于真实 NSOpenPanel 外部目录授权，普通 App 退出/重启后外部目录 IO 尚未人工验收，请按上面的第 9–11 步检查。
