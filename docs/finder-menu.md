# Finder 右键菜单试用

## 当前可试用内容

Finder Sync 扩展名：**右键助手 Finder 菜单**。当前范围：**启动磁盘及所有已挂载磁盘的普通文件夹**，包括桌面、文稿、下载、其他工作目录及外接盘目录。磁盘挂载、卸载或重命名后自动刷新。Finder 的“最近使用”等虚拟页面不代表一个可写文件夹。

- 文件夹空白处或单个文件夹右键：右键助手 → 新建 Word / PowerPoint / Excel 文档…
- 单个普通文件右键：右键助手 → 移动此文件…
- 多选或无法读取文件类型时：只提供打开右键助手。
- 新建菜单在后台直接生成文档，**不再弹出主界面、也不再要求逐个文件夹授权**。默认名为“新建 Word 文档.docx”等；同名自动使用“(2)”“(3)”编号，不覆盖已有文件。
- 移动菜单弹出目的地窗口（标题含源文件名，按钮“移动到此文件夹”，显示源路径与实际目标，选回源文件夹会被拒绝），确认后后台移动。
- 若目的地已有同名文件，会弹出选择：**保留两者**（自动改名为“名称 (2)”等）、**替换**（原子替换同名文件）、**取消**。默认“绝不覆盖”，只有选择“替换”才会覆盖。

## 权限与运行方式（2026-10-16 更新）

- 应用已**移除沙盒**，改为普通应用。文件夹访问交给 macOS 的 **“文件与文件夹”系统提示**：第一次访问桌面 / 文稿 / 下载 / 外接盘时会自动弹出一次“允许访问”，点一次即可，之后不再打扰。
- **不再引导“完全磁盘访问”**（该权限只能手动添加，且非必需）。首次启动会主动读取这三个常用目录，把系统授权提示一次性提前触发；也可在菜单栏面板点“请求授权…”再次触发。
- 应用改为**菜单栏工具**（无 Dock 图标、不自动弹窗）。之后右键操作全部后台完成。
- 通过菜单栏图标可随时查看扩展状态、管理扩展、请求文件夹授权与退出。
- 系统保护目录（如 `~/Library` 部分区域、`/System`）与只读磁盘仍不可写。

菜单中的路径只用于定位授权位置；最终操作使用已有授权根派生的目标或选择窗口返回的位置。授权时若选择了右键目录的父目录，仍在原右键目录创建；如果选择了无关目录，则在实际选择目录创建。Finder 扩展不直接写文件，也不使用主 App 的安全书签。新建成功后主 App 会显示实际文件名和所在目录。

**减少授权次数**：在设置窗口的“文件夹授权”点击“授权文件夹…”或“更换授权…”，选择常用父目录，例如“文稿”或工作文件夹，即可在其所有子目录右键创建。也可以选择某个磁盘根，覆盖其系统允许访问的子目录。目前记住一份创建授权根，切换新的根会替换之前保存的设置；重启恢复该根。授权区始终显示根目录，不随最近创建子目录变化。系统保护目录、没有写权限的文件夹和只读磁盘仍无法创建；不需要为显示菜单开启“全磁盘访问”。

## 启用与体验

1. 在 Xcode 打开 `rightchick.xcodeproj`，运行 `rightchick` / My Mac。应用构建会自动构建并嵌入 FinderExtension。
2. App 的“Finder 右键菜单”区显示扩展启用状态。未启用时点击“管理 Finder 扩展…”，在系统界面开启“右键助手 Finder 菜单”。如果系统页面变化，可在系统设置搜索“扩展”，进入 Finder 扩展管理。
3. 在 Finder 打开任意普通文件夹（例如下载、文稿或外接盘上的工作目录），空白处右键，找“右键助手”。本轮命令行已注册并设置 use；若状态尚未刷新，关闭该 Finder 窗口后再打开。
4. 点击新建 Word 文档…，首次授权窗口中确认创建目录后应自动生成“新建 Word 文档.docx”，无需再点创建按钮。再次从同一目录点击菜单，应直接创建带编号的新文件。可在 Finder 重命名生成文件。
5. 在设置窗口授权一个父目录，再到其两个不同子文件夹右键创建，检查不用重复授权且文件各自出现在对应子目录。重启 App 后同样检查。
6. 在任意普通文件夹选择一个专用测试文件，右键 → 移动此文件…；在授权窗口选择该文件，接着选择同一磁盘的目的地，确认后自动移动。
7. 验证取消授权时旧设置保留；多选时不出现批量移动；正在操作时新请求提示完成后重试。插入外接盘后打开其文件夹验证菜单。

## 移动反馈修正（2026-10-16）

用户反馈“桌面移动新建文件到文稿，显示已在此文件夹中”。处理方式不是放宽无覆盖/同目录保护，而是消除两次通用选择面板的歧义并复用源授权：

- 目的地窗口独立于目录授权窗口：标题含源文件名，按钮“移动到此文件夹”，说明显示源路径并提示侧栏“文稿”，窗内附件实时显示实际目标；选回源文件夹会在确认前被拒绝。
- 源文件位于已授权创建根内时，直接复用该授权包围移动，跳过源文件授权面板。
- 记录私有的源/目标路径与成功/失败阶段，便于后续诊断（不公开完整路径）。
- 最终 **100 项测试通过**，无失败/跳过/runtimeWarnings；已在 Xcode 副本重建并重启运行。真实系统面板点击仍待人工验收。结果：`/var/folders/2m/wsdtb63j6hl_24pwvwnbjp980000gn/T/opencode/rightchick-movefix-tests.xcresult`。

有多个开发副本时，确保只运行当前构建。菜单点选会明确打开包含该扩展的 App，避免 URL scheme 打开其他副本。正式安装和分发还需要稳定安装位置与开发者签名配置。

## 本轮本机验证（2026-10-12，America/Los_Angeles）

- 本地临时签名的 Debug 主 App + Finder 扩展构建成功，无 Swift 编译警告。
- 应用 `Contents/PlugIns/FinderExtension.appex` 已嵌入；principal class 为 `FinderExtension.FinderSync`；扩展点为 `com.apple.FinderSync`；最低 macOS 14.0。
- 深度签名验证通过；扩展仅带 Sandbox 和 Debug 调试权限，应用保留原有用户选择读写和 app-scope 书签权限，无 App Group。
- `pluginkit -a` 注册成功；`pluginkit -e use` 后查询出现 `+ devplaceholder.JW2H7X4Z.rightchick.FinderExtension(1.0)`。打开普通 App 和桌面后，pgrep 确认主 App 与 FinderExtension 两个进程实际运行。
- 最终 **69 项测试通过，0 失败、0 跳过、无 runtimeWarnings**。新增 9 项测试覆盖交接 URL、非法输入、中文特殊字符、真实用户桌面范围、授权取消与实际选择；原有异步测试增加忙碌请求拒绝。
- 首次测试发现 Foundation 的 `NSHomeDirectoryForUser` 在测试沙盒中也会重定向容器；改为 `getpwuid_r` 获取真实用户 home，避免监控错误的容器 Desktop。回归测试保留。
- 没有桌面交互工具，本轮不能直接观察菜单画面或点击菜单。扩展已注册、已选用且进程运行，不等同于菜单显示和点选端到端已验收。

当前普通 App：

`/var/folders/2m/wsdtb63j6hl_24pwvwnbjp980000gn/T/opencode/rightchick-m5-derived/Build/Products/Debug/rightchick.app`

测试结果：

`/var/folders/2m/wsdtb63j6hl_24pwvwnbjp980000gn/T/opencode/rightchick-m5-final-tests.xcresult`

### 菜单自动新建修正（2026-10-12）

根据用户反馈，将原先“准备输入后手动创建”的流程改为菜单自动创建。已验证同目录授权复用、不同目录授权、取消保留、排队/授权期间互斥、失败提示、关闭取消，以及真实三种文档的递增命名与并发无覆盖。

修正后 **78 项测试通过，0 失败、0 跳过、无 runtimeWarnings**，普通 App 已在上述相同位置重新构建、注册并打开，深度签名验证通过。结果：`/var/folders/2m/wsdtb63j6hl_24pwvwnbjp980000gn/T/opencode/rightchick-autocreate-tests.xcresult`。真实 Finder 点选后的系统授权与输出画面仍待验收。

### 菜单点击交接修正与真实输出（2026-10-12）

用户报告没有授权窗口后，修复了扩展依赖菜单 `representedObject` 的交接：改用 Finder 回传的 `tag` 查询扩展本地请求表。另增加点击、主 App 打开及 URL 接收日志；没有保存文档路径到公开日志。

已重建并启动用户实际使用的 Xcode 副本：

`/Users/xkwang/Library/Developer/Xcode/DerivedData/rightchick-caldmekacyazmsdfowugkojxwgms/Build/Products/Debug/rightchick.app`

**真实菜单新建已走通**：日志记录扩展收到 tag 2、App 打开成功、SwiftUI 接收 `powerPoint` 请求；桌面实际生成“新建 PowerPoint 文档.pptx”，SHA-256 与合法空白模板一致。已有桌面授权，因此没有弹授权窗口是正常行为。另通过系统 URL 验证生成“新建 Word 文档.docx”。生成文档保留供检查。

最终 **81 项测试通过**，无失败/跳过/runtimeWarnings，构建和深度签名验证通过。结果：`/var/folders/2m/wsdtb63j6hl_24pwvwnbjp980000gn/T/opencode/rightchick-menu-tag-tests.xcresult`。首次无授权目录的真实面板与移动菜单流程仍需验收。

## 若没有出现

先确认打开的是 Finder 普通文件夹，并在 App 检查已启用状态。再打开系统 Finder 扩展管理关闭/开启该扩展、重开 Finder 窗口。若仍无菜单，将 App 显示的状态和系统扩展页截图用于继续定位；不需要先给全磁盘或辅助功能权限。

命令行诊断（当前开发 Bundle ID）：

```sh
pluginkit -m -Avv -i devplaceholder.JW2H7X4Z.rightchick.FinderExtension
pgrep -fl FinderExtension
```

关闭本轮扩展：

```sh
pluginkit -e ignore -i devplaceholder.JW2H7X4Z.rightchick.FinderExtension
```

## 全磁盘文件夹版本验证（2026-10-16）

- 注册 `/` 与所有挂载卷根，监听挂载、卸载、卷重命名，仅注册范围，不扫描文件。
- 新增父目录授权匹配与根作用域生命周期，手动/自动创建都保持根授权直到异步创建结束。书签格式兼容原配置；保存授权根，不保存最近子目录代替根。
- **90 项测试全部通过**，0 失败、0 跳过、无 runtimeWarnings。验证路径组件边界、同名前缀、跨卷、取消、清除根、重启恢复根，以及真实临时目录中父授权下创建三种 Office 文件。所有既有同名保护与移动测试通过。
- 独立 Debug 应用构建与深度签名检查通过，无编译警告；已重建 Xcode 常用副本，重新注册并启用扩展，重启 Finder 后主 App 和扩展均从该副本运行。
- 实际扩展日志记录 `Finder menu scope updated, volume roots: 11`，证实本机新范围已注册。已打开“下载”文件夹供试用；桌面外菜单画面、外接盘插拔及第三方云盘尚未实际点选验收。
- 测试结果：`/var/folders/2m/wsdtb63j6hl_24pwvwnbjp980000gn/T/opencode/rightchick-allfolders-final-tests.xcresult`。
- 当前运行 App：`/Users/xkwang/Library/Developer/Xcode/DerivedData/rightchick-caldmekacyazmsdfowugkojxwgms/Build/Products/Debug/rightchick.app`。

## 精简设置窗口（2026-10-16）

主窗口只保留扩展启用状态、文件夹授权（选择/更换/清除），以及按需显示的最近结果和“在 Finder 中显示”。新建类型、名称输入、预览、源文件及移动按钮表单已移除。文件移动也能由菜单和系统选择窗口完整完成。关闭设置窗口不会取消已发起的菜单文件操作。

最终 **96 项测试通过**，0 失败、0 跳过、无 runtimeWarnings；包括菜单移动成功、两个选择窗口取消、重复/嵌套请求、失败、排队取消、实际临时文件无按钮移动和结果链接更新。构建与深度签名通过，已打开新版 App。结果：`/var/folders/2m/wsdtb63j6hl_24pwvwnbjp980000gn/T/opencode/rightchick-compact-final-tests.xcresult`。紧凑布局与真实 NSOpenPanel 移动流程仍需人工体验验收。
