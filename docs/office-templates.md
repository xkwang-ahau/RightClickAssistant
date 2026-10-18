# Office 空白模板来源和验证

这三个资源是项目脚本生成的有效 OOXML 文件，用于创建新文档。App 仅复制打包的资源，无需安装 Python、LibreOffice 或 Microsoft Office；编辑文档需要支持相应格式的软件。

| 资源 | 空白内容 | 生成工具 |
| --- | --- | --- |
| BlankWord.docx | 一个空白段落 | python-docx 1.2.0 |
| BlankPowerPoint.pptx | 一张 16:9 空白幻灯片 | python-pptx 1.0.2 |
| BlankExcel.xlsx | 一个名为“工作表1”的空白工作表 | openpyxl 3.1.5 |

来源是各库提供的标准空白文档构造器，没有从用户的办公文档提取内容。模板清除了作者及最后编辑者信息，固定创建/修改日期与 ZIP 时间戳。哈希、字节数和生成库版本记录在 office-template-manifest.json。生成库采用 MIT 许可，不会作为 App 的运行时依赖打包；其版权及许可说明保存于 Resources/OfficeTemplateLicenses.txt，随模板一起打包。

重建步骤：用装有对应库的 Python 执行 `scripts/generate_office_templates.py`，再执行 `scripts/verify_office_templates.py`。验证脚本检查哈希、ZIP CRC、所有 XML、内部关系完整性、无外部关系、库读取和空白内容。还应对构建产物的 Contents/Resources 运行同样的验证，确保资源已打包。

## 验证记录（2026-10-06）

- 源资源及已构建 App 内资源均通过哈希、ZIP CRC、XML、内部关系及库读取检查，空白内容正确。
- App 的 XCTest 实际创建三种文件，并验证输出与 Bundle 模板字节完全一致。
- 已安装的 LibreOffice 成功将 Word / PowerPoint / Excel 模板分别读取并转换为 ODT / ODP / ODS，三个命令均返回 0，且输出有效 ZIP 文档。
- Microsoft Word / PowerPoint / Excel 的真实打开与修复提示检查尚未验证：窗口自动化服务中断，无法操作和观察真实窗口。这些结构及 LibreOffice 检查不能替代 Microsoft Office 的实际打开验证。
