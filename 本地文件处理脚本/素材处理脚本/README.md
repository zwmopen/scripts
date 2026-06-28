# 素材处理脚本

这里放素材采集、整理、预览、同步相关的效率工具。它们不一定都是传统意义上的脚本，也可以是一个可复用工作流、一个双击按钮安装器，或者一个本地 skill。

## 目前收录

1. `江湖采集下载文件夹过长处理脚本.ps1`

   用来处理小红书、抖音采集素材里过长的帖子文件夹名和文件名，保留点赞、评论、收藏、作者、标题等关键信息，去掉后面的正文、摘要、标签，避免浏览器拖拽上传文件夹时因为路径过长失效。

   常用方式：

   ```powershell
   powershell -ExecutionPolicy Bypass -File ".\江湖采集下载文件夹过长处理脚本.ps1" -RootPath "D:\AICode\AI\data\01-团建策划-江湖有旅人\01-素材库\1.团建攻略素材" -Mode Preview
   powershell -ExecutionPolicy Bypass -File ".\江湖采集下载文件夹过长处理脚本.ps1" -RootPath "D:\AICode\AI\data\01-团建策划-江湖有旅人\01-素材库\1.团建攻略素材" -Mode Apply
   powershell -ExecutionPolicy Bypass -File ".\江湖采集下载文件夹过长处理脚本.ps1" -RootPath "D:\AICode\AI\data\01-团建策划-江湖有旅人\01-素材库\1.团建攻略素材" -Mode Undo
   ```

2. `安装-一键生成硬链接封面.py`

   给任意素材文件夹安装一个“双击刷新预览”的小工具。安装后，它会在目标文件夹里生成：

   - `更新预览硬链接.py`
   - `双击更新预览硬链接.bat`

   之后双击 bat，就会把每个帖子/模板文件夹的前几张图做成硬链接封面预览，不复制原文件，省空间。

   常用方式：

   ```powershell
   python ".\安装-一键生成硬链接封面.py" "D:\你的素材文件夹" --run
   ```

3. `同步-硬链接素材工作副本.ps1`

   从原素材目录同步一份“工作副本”到另一个目录。默认使用硬链接，几乎不占额外空间，适合拿来改文件名、移动、筛选、组装素材。

   重要提醒：硬链接文件改名、移动，不影响原路径；但如果直接修改图片、视频、文档的内容，原素材也会跟着变。要改内容时，用 `-SyncType Copy` 做真实复制。

   常用方式：

   ```powershell
   powershell -ExecutionPolicy Bypass -File ".\同步-硬链接素材工作副本.ps1" -SourcePath "D:\原素材" -TargetPath "D:\工作副本" -Mode Preview
   powershell -ExecutionPolicy Bypass -File ".\同步-硬链接素材工作副本.ps1" -SourcePath "D:\原素材" -TargetPath "D:\工作副本" -Mode Apply
   powershell -ExecutionPolicy Bypass -File ".\同步-硬链接素材工作副本.ps1" -SourcePath "D:\原素材" -TargetPath "D:\工作副本" -Mode Apply -SyncType Copy
   ```

## 收录原则

- 已经帮自己省过时间，未来还会重复用。
- 可以是脚本，也可以是一个工作流、一个 skill、一个双击按钮安装器。
- 优先保留能独立运行、能迁移到别的项目里的工具。
- 一次性临时处理脚本，除非以后明显还会复用，否则不放进来。
