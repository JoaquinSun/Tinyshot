# GitHub 发布准备

本指南用于首次上传与后续发布。仓库不包含个人配置、截图、运行数据或本机构建的应用。

## 上传前检查

```sh
python3 scripts/check-public.py
zsh scripts/test.sh
zsh scripts/build.sh
git status --short
git diff --cached --stat
python3 scripts/check-public.py --staged
```

默认扫描工作区中 Git 已跟踪及未被忽略的文件；`--staged` 检查暂存区的实际内容。扫描只输出问题类型和位置，不回显匹配到的秘密。基础规则不能覆盖所有隐私形式，特别是图片内容。新增素材应使用生成示例，逐张人工检查。

本地 `dist/` 和 `.build/` 可能包含机器路径，已排除。不要通过 `git add -f` 加入这些目录，也不要直接压缩整个项目文件夹用于公开。

## 提交身份与首次上传

Git 提交会公开作者名称和邮箱。提交前在 GitHub 设置中取得自己的隐私邮箱（noreply），并仅为本仓库设置你希望公开的名称与邮箱：

```sh
git config --local user.name 'YOUR_PUBLIC_NAME'
git config --local user.email 'YOUR_GITHUB_NOREPLY_EMAIL'
```

替换占位符后再执行；不必修改全局 Git 身份。请在设置好公开提交身份后再创建首次提交，避免沿用机器上的私人作者信息。

确认暂存内容后创建提交：

```sh
git add .
python3 scripts/check-public.py --staged
git diff --cached --stat
git commit -m "Prepare TinyShot for open source"
git log -1 --format=fuller
```

在 GitHub 创建空仓库（不额外生成 README 或许可证）。确认提交中的作者信息是你愿意公开的，再添加远程地址并上传：

```sh
git remote add origin https://github.com/YOUR_ACCOUNT/TinyShot.git
git push -u origin main
```

仓库从零初始化，没有旧提交历史需要清理。未来若秘密进入历史，仅删除当前文件不足以清除历史；应先撤销受影响的凭据，再处理历史。

## 干净的源码压缩包

先暂存希望公开的文件，然后运行：

```sh
python3 scripts/export-source.py
```

脚本扫描并仅打包 Git 暂存区快照，输出 `dist/TinyShot-source-v版本号.zip`。包内包含一个 `TinyShot/` 目录，不含 `.git`、本地应用或缓存；ZIP 不带本机所有者、扩展属性和绝对路径。未暂存的改动不会进入源码包。

## 后续应用发布

修改版本时同步更新 `Resources/Info.plist` 中的显示版本与构建号。当前脚本只生成构建机器架构的临时本地签名应用，尚未提供 Developer ID 签名、公证或通用二进制包。

GitHub Actions 使用 macOS 26 和指定 Xcode 26 工具链执行扫描、测试及构建，只读仓库内容，不自动上传应用或发布 Release。首次上传后需在 GitHub 检查实际 CI 结果；本地通过不等于远端已通过。
