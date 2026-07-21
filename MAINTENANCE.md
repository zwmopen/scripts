# 维护与发布

## 检查镜像

在 PowerShell 中运行：

```powershell
.\maintenance\sync-managed-mirrors.ps1
```

脚本默认只检查，不写文件。任一镜像缺失或内容不同都会返回失败。

## 更新镜像

确认独立项目中的真源已经通过测试后运行：

```powershell
.\maintenance\sync-managed-mirrors.ps1 -Apply
.\maintenance\sync-managed-mirrors.ps1
```

随后分别提交独立项目和本发布仓库。若未发布本仓库，现有在线安装用户不会收到独立项目里的新版本。
