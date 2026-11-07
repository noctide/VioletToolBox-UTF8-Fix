# VioletToolBox UTF-8 修复版（中文乱码修复）

> **本项目不是原作者项目，而是对上游的 bug 修复补丁。**
> 原作者：**Smart-Paocai** · 上游仓库：<https://github.com/Smart-Paocai/VioletToolBox>

---

## 一、链路（Provenance）

```
原作者 Smart-Paocai
      │
      │  https://github.com/Smart-Paocai/VioletToolBox
      │  GPL-3.0
      ▼
上游源码 commit 153a0d13a0ae855c3e682bf281940e691ef22f21
（2026-10-23，"Update star history links in README.md"）
      │
      │  本仓库提供的补丁 patch/0001-fix-utf8-adb-output.patch
      │  （仅修改 VioletToolBox/MainWindow.xaml.cs，2 行有效改动）
      ▼
本仓库：VioletToolBox-UTF8-Fix
      │
      │  构建产物（可选）
      ▼
VioletToolBox.exe（UTF-8 修复版）
```

### 归属声明

| 项目 | 归属 |
|---|---|
| VioletToolBox 全部代码 | **Smart-Paocai** 及上游贡献者 |
| 本项目新增内容 | 仅 `patch/` 中的 UTF-8 编码修复补丁 + 本文档 |
| 许可证 | **GPL-3.0**（与上游一致，见 [LICENSE](LICENSE)） |
| 官方下载 | <https://github.com/Smart-Paocai/VioletToolBox/releases> |

---

## 二、修复的问题

**现象**：设备信息面板中「版本信息」显示乱码。

| | 显示内容 |
|---|---|
| 修复前 | `ä¸å±è®¢æ°` ❌ |
| 修复后 | `已屏蔽更新` ✅ |

受影响的不止这一个字段——**所有从 adb 读取的中文字符串**都会乱码。

---

## 三、根因

### 3.1 出问题的代码

`VioletToolBox/MainWindow.xaml.cs` → `GetCommandOutput()`：

```csharp
process = new Process
{
    StartInfo = new ProcessStartInfo
    {
        FileName = fileName,
        Arguments = arguments,
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        CreateNoWindow = true
        // ← 没有设置 StandardOutputEncoding
    }
};
```

### 3.2 为什么会导致乱码

| 环节 | 编码 |
|---|---|
| `adb` / `fastboot` 输出 | **UTF-8** |
| .NET 未指定 `StandardOutputEncoding` 时的默认解码 | **系统 OEM 代码页**（中文 Windows = GBK / 936） |

UTF-8 字节被按 GBK 解释 → 中文乱码。

### 3.3 实测对照

设备属性 `ro.build.version.incremental` 的实际值 = `已屏蔽更新`

| 解码方式 | 结果 |
|---|---|
| UTF-8（正确） | `已屏蔽更新` |
| Latin-1 | `å·²å±è½æ´æ°` |
| GBK (936) | `宸插睆钄芥洿鏂?` |

### 3.4 为什么只有部分设备暴露这个问题

`UpdateVersionInfoAsync()` 的逻辑：

```csharp
if (char.IsUpper(deviceCode[0]))
    command = "shell getprop ro.build.display.id";          // 通常是 ASCII
else
    command = "shell getprop ro.build.version.incremental";  // 可能含中文
```

- 设备代号首字母**大写** → 读 `ro.build.display.id`（纯 ASCII，看不出异常）
- 设备代号首字母**小写**（如 `rubens`）→ 读 `ro.build.version.incremental`（可能含中文）→ **乱码暴露**

本次复现设备：Redmi K50（代号 `rubens`），且该属性被「屏蔽更新」模块改成了中文 `已屏蔽更新`，因此必然触发。

---

## 四、修复

```diff
--- a/VioletToolBox/MainWindow.xaml.cs
+++ b/VioletToolBox/MainWindow.xaml.cs
@@ -8284,7 +8284,12 @@
                         UseShellExecute = false,
                         RedirectStandardOutput = true,
                         RedirectStandardError = true,
-                        CreateNoWindow = true
+                        CreateNoWindow = true,
+                        // adb / fastboot 的输出统一为 UTF-8。
+                        // 不显式指定时 .NET 会按系统 OEM 代码页（中文 Windows 为 GBK/936）解码，
+                        // 导致设备返回的中文属性值（如 ro.build.version.incremental）显示为乱码。
+                        StandardOutputEncoding = new UTF8Encoding(false),
+                        StandardErrorEncoding = new UTF8Encoding(false)
                     }
                 };
```

### 为什么只改这一处

`GetCommandOutput()` 共有 **61 处调用**，全部传入 `adb.exe` 或 `fastboot.exe`，两者输出均为 UTF-8，因此统一 UTF-8 解码对所有调用方都是正确的。

### 已验证

- 修复版运行后「版本信息」正确显示 `已屏蔽更新`
- 设备连接、电池温度、存储/内存、解锁状态、内核版本、构建日期等字段全部正常
- 编译：`0 错误`（393 个警告均为上游原有的 nullable 警告）

截图见 [docs/](docs/)。

---

## 五、如何使用

### 方式 A：自己打补丁编译（推荐）

```powershell
# 1. 克隆上游
git clone https://github.com/Smart-Paocai/VioletToolBox.git
cd VioletToolBox

# 2. 切到本项目对应的上游版本
git checkout 153a0d13a0ae855c3e682bf281940e691ef22f21

# 3. 应用补丁
git apply path\to\0001-fix-utf8-adb-output.patch

# 4. 编译
dotnet build VioletToolBox/SmartTool.csproj -c Release

# 5. 发布单文件
dotnet publish VioletToolBox/SmartTool.csproj -c Release -r win-x64 `
  --self-contained false -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true -o ..\out
```

**环境要求**：.NET 8 SDK（或更高版本 SDK 编译 net8.0-windows 目标）

### 方式 B：使用已构建版本

如果本项目 Release 中提供了构建产物：

1. 解压完整目录（**不要只留 exe**，需要 `LKM_Patch`、`KernelPatch`、`exe` 等运行依赖）
2. 确保已安装 **.NET 8 Desktop Runtime (x64)**
   <https://dotnet.microsoft.com/download/dotnet/8.0>
3. 建议把 `platform-tools\`（含 adb.exe / fastboot.exe）放到程序目录
4. 双击 `VioletToolBox.exe`

---

## 六、目录结构

```
.
├── README.md                              # 本文件
├── LICENSE                                # GPL-3.0（来自上游）
├── patch/
│   └── 0001-fix-utf8-adb-output.patch     # 修复补丁（1 KB）
└── docs/
    ├── after-connected.png                # 修复后：版本信息正确显示
    ├── after-published.png                # 修复后：发布版运行效果
    └── after-window.png                   # 修复后：窗口全貌
```

---

## 七、给上游的建议

建议向 <https://github.com/Smart-Paocai/VioletToolBox> 提交 Issue / PR：

1. **本补丁**：`GetCommandOutput()` 显式使用 UTF-8
2. **同类隐患**：`ConfigureHiddenRedirectedProcess()`（`MainWindow.xaml.cs:14287` 附近）在调用方未指定编码时会回退到 `CultureInfo.CurrentCulture.TextInfo.OEMCodePage`。若有 adb 调用经过该函数且输出含中文，同样会乱码。
3. 上游 v3.7 发布版（`V3.7_Release.exe`）经实测存在此问题。

---

## 八、许可证

本项目遵循 **GNU General Public License v3.0**（与上游一致）。

- 上游代码版权归 **Smart-Paocai** 及贡献者所有
- 本仓库新增的补丁与文档同样以 GPL-3.0 发布
- 完整源码 = 上游仓库（commit `153a0d1`）+ 本仓库 `patch/`
