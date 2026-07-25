# 使用 Launchpad PPA 发布和维护 netwtop

本文档说明如何把 `netwtop` 的 Debian 源码包上传到 Launchpad PPA，由
Launchpad 构建、签名并托管 Ubuntu 软件包，使用户可以通过以下命令安装和
接收更新：

```sh
sudo add-apt-repository ppa:YOUR_LAUNCHPAD_ID/netwtop
sudo apt update
sudo apt install netwtop
```

本文以当前项目状态为例：

| 项目 | 当前值 |
| --- | --- |
| Source package | `netwtop` |
| Upstream version | `0.1.1` |
| Existing package version | `0.1.1-1~netwtop1` |
| Initial Ubuntu series | Ubuntu 22.04 LTS `jammy` |
| Package architecture | `all` |
| Launchpad account email | `eddyxu2000@gmail.com` |
| PPA maintainer identity | `DoubleFlicker7 <eddyxu2000@gmail.com>` |
| Source upload key | `031287FF50C1770AE7E70A56C9B2395F128D2B52` |
| Recommended first PPA version | `0.1.1-1~ppa1~ubuntu22.04.1` |
| Recommended PPA name | `netwtop` |

文中的 `YOUR_LAUNCHPAD_ID` 必须替换为实际 Launchpad ID。不要直接把带有
`YOUR_...` 的示例命令用于正式上传。

## 1. 理解 PPA 发布链路

PPA 发布过程如下：

```text
Git release
    -> Debian source package
    -> maintainer-signed source.changes
    -> dput upload
    -> Launchpad source acceptance
    -> Launchpad clean build
    -> Launchpad-signed APT repository
    -> apt install netwtop
```

PPA 只接受源码上传。不要上传本地构建的 `.deb` 或 binary/mixed
`.changes`；Launchpad 会在自己的构建环境中生成二进制包。

PPA 涉及两种不同的签名身份：

1. **源码上传密钥**：由维护者持有，用于签名 `.dsc` 和
   `_source.changes`。该密钥的公钥必须注册到 Launchpad。
2. **PPA archive key**：由 Launchpad 在首次成功上传后生成并管理，用于
   签名用户下载的 APT 仓库元数据。

不要创建或维护第二套本地 archive key，也不要把私钥上传到 Launchpad。

## 2. 准备本地变量

后续示例使用以下变量。首先填写真实的 Launchpad ID：

```sh
NETWTOP_ROOT='/data/xuhaonan/project/NetworkMonitor'
NETWTOP_PARENT='/data/xuhaonan/project'
NETWTOP_UPSTREAM_VERSION='0.1.1'
NETWTOP_PPA_VERSION='0.1.1-1~ppa1~ubuntu22.04.1'
NETWTOP_SERIES='jammy'
NETWTOP_KEY='031287FF50C1770AE7E70A56C9B2395F128D2B52'
NETWTOP_LP_ID='YOUR_LAUNCHPAD_ID'
NETWTOP_PPA="ppa:${NETWTOP_LP_ID}/netwtop"
```

确认没有保留占位符：

```sh
test "$NETWTOP_LP_ID" != 'YOUR_LAUNCHPAD_ID' || {
    printf '%s\n' 'Error: Set NETWTOP_LP_ID before continuing.' >&2
    return 1 2>/dev/null || exit 1
}
```

## 3. 建立可追溯的发布基线

PPA 不强制要求 Git 工作区干净，但正式发布必须能够追溯到明确的提交和标签。
先检查当前状态：

```sh
cd "$NETWTOP_ROOT"
git status --short
git diff --check
./tests/smoke.sh
```

确认以下内容已经纳入版本控制：

- `debian/` Debian 打包元数据；
- `man/netwtop.1`；
- `bin/netwtop` 中的版本、`CHANGELOG.md` 和实际运行时源码；
- 本文档及相关发布说明。

提交发布基线时，只添加已经审阅过的文件：

```sh
git add .gitignore CHANGELOG.md README.md \
    bin docs man src tests debian install.sh netwtop
git diff --cached --check
git status --short
git commit -m 'Prepare netwtop 0.1.1 PPA packaging'
```

先检查本地和远端是否已经存在 `v0.1.1`：

```sh
git tag --list 'v0.1.1'
git ls-remote --tags origin 'refs/tags/v0.1.1'
```

如果标签已经存在，不要移动或覆盖它；确认它确实指向 `0.1.1` 发布提交。
只有在标签不存在时才创建并推送签名标签：

```sh
git tag -s -u "$NETWTOP_KEY" -m 'netwtop 0.1.1' v0.1.1
git push origin HEAD
git push origin v0.1.1
```

## 4. 准备 Launchpad 账号和源码上传密钥

### 4.1 创建或登录 Launchpad

访问 <https://launchpad.net/>，通过 Ubuntu One 登录，并确认邮箱已经验证。
本项目使用以下 Launchpad 账号邮箱：

```text
eddyxu2000@gmail.com
```

同时接受 Launchpad 服务条款及其中包含的 Ubuntu Code of Conduct。Launchpad
登录邮箱、Debian Maintainer/Changed-By 邮箱和 OpenPGP UID 是不同字段；它们
技术上可以不同，但为了避免上传通知和身份识别问题，本流程把新的 PPA 上传
身份统一为 Gmail。

### 4.2 核对现有源码上传密钥

```sh
gpg --list-secret-keys --keyid-format long "$NETWTOP_KEY"
gpg --fingerprint "$NETWTOP_KEY"
```

预期完整指纹为：

```text
031287FF50C1770AE7E70A56C9B2395F128D2B52
```

当前密钥最初使用的 UID 是 `DoubleFlicker7 <eddyxu2000@163.com>`。在首次
导入 Launchpad 之前，为同一密钥增加 Gmail UID：

```sh
gpg --quick-add-uid "$NETWTOP_KEY" \
    'DoubleFlicker7 <eddyxu2000@gmail.com>'
```

该命令会要求输入私钥 passphrase。新增 UID 不会改变密钥指纹，旧 UID 也
不必删除。完成后核对两个 UID 和同一个指纹：

```sh
gpg --list-keys --keyid-format long "$NETWTOP_KEY"
gpg --fingerprint "$NETWTOP_KEY"
```

如果你选择继续用 `@163.com` 作为 Debian 上传身份，也可以在 Launchpad 中
把它添加为经过验证的附加邮箱；本项目默认采用 Gmail 统一方案。

### 4.3 发布更新后的公钥并导入 Launchpad

只向 Ubuntu keyserver 发布公钥；以下命令不会上传私钥：

```sh
gpg --keyserver keyserver.ubuntu.com --send-keys "$NETWTOP_KEY"
```

必须在新增 Gmail UID 后再执行上述发送命令。keyserver 同步可能需要约
30 分钟。随后访问：

```text
https://launchpad.net/~YOUR_LAUNCHPAD_ID/+editpgpkeys
```

输入完整指纹并选择 **Import Key**。Launchpad 会向 Gmail 账号邮箱发送一封由该
公钥加密的确认邮件。如果邮件客户端不能解密，可以把包含
`BEGIN PGP MESSAGE` 和 `END PGP MESSAGE` 的完整内容保存到临时文件后执行：

```sh
gpg --decrypt /tmp/launchpad-key-confirmation.asc
```

按照解密邮件中的链接完成确认，然后在 Launchpad 个人页面核对该指纹已经
处于有效状态。确认完成后删除临时邮件文件：

```sh
rm -f -- /tmp/launchpad-key-confirmation.asc
```

## 5. 创建 netwtop PPA

### 5.1 推荐：通过 Launchpad 网页创建

打开个人页面并选择 **Create a new PPA**，建议填写：

| 字段 | 建议值 |
| --- | --- |
| URL name | `netwtop` |
| Display name | `netwtop stable releases` |
| Description | `Stable Ubuntu packages for netwtop` |

创建后 PPA 引用应为：

```text
ppa:YOUR_LAUNCHPAD_ID/netwtop
```

### 5.2 可选：使用 ppa-dev-tools

不需要 CLI 管理时可以跳过本节。需要时安装并创建：

```sh
sudo snap install ppa-dev-tools
ppa create netwtop
```

首次调用会要求在浏览器中授权 Launchpad API。

## 6. 采用 PPA 专用版本号

当前已经使用过的本地仓库版本是：

```text
0.1.1-1~netwtop1
```

首次 PPA 上传建议使用：

```text
0.1.1-1~ppa1~ubuntu22.04.1
```

这个版本高于旧项目仓库版本，同时低于未来可能进入 Ubuntu/Debian 官方仓库
的 `0.1.1-1`。验证排序关系：

旧的 `0.1.1-1~netwtop1` changelog trailer 仍记录原来的 `@163.com`，这是
既有构建的历史信息，不需要重写。下面创建的新 PPA revision 会使用 Gmail
作为 Changed-By/Maintainer 身份。

```sh
dpkg --compare-versions \
    '0.1.1-1~ppa1~ubuntu22.04.1' \
    gt '0.1.1-1~netwtop1' && \
    printf '%s\n' 'PPA upgrade ordering: OK'

dpkg --compare-versions \
    '0.1.1-1' \
    gt '0.1.1-1~ppa1~ubuntu22.04.1' && \
    printf '%s\n' 'Official archive migration ordering: OK'
```

在 `debian/changelog` 创建新的 PPA revision：

```sh
cd "$NETWTOP_ROOT"
DEBFULLNAME='DoubleFlicker7' \
DEBEMAIL='eddyxu2000@gmail.com' \
dch --newversion "$NETWTOP_PPA_VERSION" \
    --distribution "$NETWTOP_SERIES" \
    'Publish netwtop through the Launchpad PPA.'
```

检查解析结果：

```sh
dpkg-parsechangelog -S Source
dpkg-parsechangelog -S Version
dpkg-parsechangelog -S Distribution
dpkg-parsechangelog -S Maintainer
```

预期结果分别为：

```text
netwtop
0.1.1-1~ppa1~ubuntu22.04.1
jammy
DoubleFlicker7 <eddyxu2000@gmail.com>
```

提交 PPA revision：

```sh
git add debian/changelog
git diff --cached --check
git commit -m 'Prepare 0.1.1 PPA revision for Jammy'
```

## 7. 准备 upstream orig tarball

`3.0 (quilt)` 源码包首次上传某个上游版本时需要：

```text
netwtop_0.1.1.orig.tar.gz
```

推荐从已经推送的不可变 `v0.1.1` GitHub 标签下载，而不是从带有未提交修改的
工作区临时打包。当前 `debian/watch` 已指向 GitHub tags：

```sh
cd "$NETWTOP_ROOT"
uscan --download-current-version --destdir "$NETWTOP_PARENT"
```

核对产物：

```sh
test -s "$NETWTOP_PARENT/netwtop_0.1.1.orig.tar.gz"
tar -tzf "$NETWTOP_PARENT/netwtop_0.1.1.orig.tar.gz" | sed -n '1,30p'
```

如果 `uscan` 找不到 `0.1.1`，先确认：

```sh
git ls-remote --tags origin 'refs/tags/v0.1.1'
uscan --no-download --report-status
```

不要用另一个内容不同的归档覆盖 Launchpad 已经接收的同名 orig tarball；同一
upstream version 的 orig tarball 内容必须保持不变。

## 8. 构建并签名源码上传

先执行本地检查和清理：

```sh
cd "$NETWTOP_ROOT"
git status --short
git diff --check
./tests/smoke.sh
debian/rules clean
```

首次向这个 PPA 上传 `netwtop 0.1.1` 时使用 `-S -sa`：

```sh
debuild -S -sa -k"$NETWTOP_KEY"
```

参数含义：

| 参数 | 含义 |
| --- | --- |
| `-S` | 只构建源码上传，不生成要上传的二进制 `.deb` |
| `-sa` | 在 `_source.changes` 中包含 orig tarball |
| `-k...` | 使用已经注册到 Launchpad 的维护者密钥签名 |

预期生成：

```text
/data/xuhaonan/project/netwtop_0.1.1.orig.tar.gz
/data/xuhaonan/project/netwtop_0.1.1-1~ppa1~ubuntu22.04.1.debian.tar.xz
/data/xuhaonan/project/netwtop_0.1.1-1~ppa1~ubuntu22.04.1.dsc
/data/xuhaonan/project/netwtop_0.1.1-1~ppa1~ubuntu22.04.1_source.buildinfo
/data/xuhaonan/project/netwtop_0.1.1-1~ppa1~ubuntu22.04.1_source.changes
```

不要上传以下文件：

```text
*_all.deb
*_amd64.changes
```

## 9. 上传前验证

为便于复制命令，设置源码 changes 路径：

```sh
NETWTOP_CHANGES="$NETWTOP_PARENT/netwtop_${NETWTOP_PPA_VERSION}_source.changes"
test -s "$NETWTOP_CHANGES"
```

检查软件包元数据、Lintian 和签名：

```sh
sed -n '1,80p' "$NETWTOP_CHANGES"
lintian --display-info --pedantic "$NETWTOP_CHANGES"
gpg --verify "$NETWTOP_CHANGES"
```

检查上传必须满足以下条件：

```sh
grep -q '^Architecture: source$' "$NETWTOP_CHANGES"
grep -q '^Distribution: jammy$' "$NETWTOP_CHANGES"
grep -q '^Version: 0.1.1-1~ppa1~ubuntu22.04.1$' "$NETWTOP_CHANGES"
grep -q 'netwtop_0.1.1.orig.tar.gz' "$NETWTOP_CHANGES"
```

可选但推荐：从 `.dsc` 在隔离目录重新构建，并运行 autopkgtest。具体本地
Debian 包验证步骤见 [APT_PACKAGING.md](APT_PACKAGING.md)。

## 10. 检查、模拟并正式上传

本机已经安装 `dput`。先只检查上传内容：

```sh
dput -o "$NETWTOP_PPA" "$NETWTOP_CHANGES"
```

然后模拟上传：

```sh
dput -s "$NETWTOP_PPA" "$NETWTOP_CHANGES"
```

两步都确认无误后，正式上传：

```sh
dput "$NETWTOP_PPA" "$NETWTOP_CHANGES"
```

`dput` 显示传输完成不等于软件包已经被接受。Launchpad 随后会向维护者邮箱
发送 accepted 或 rejected 通知。到 PPA 页面依次确认：

1. source upload 已接受；
2. Jammy build 从 Pending 进入 Building；
3. build 状态为 Successfully built；
4. package 状态进入 Published。

首次成功上传后，Launchpad 生成 PPA archive key 可能需要数小时。archive
key 和用户安装说明会显示在 PPA overview 页面。

## 11. 在干净的 Jammy 环境安装验证

推荐使用没有配置旧项目仓库的 Ubuntu 22.04 VM 或容器。添加 PPA：

```sh
sudo add-apt-repository "$NETWTOP_PPA"
sudo apt update
```

确认候选版本和来源：

```sh
apt-cache policy netwtop
apt-cache madison netwtop
```

候选版本应为：

```text
0.1.1-1~ppa1~ubuntu22.04.1
```

执行安装和功能验证：

```sh
sudo apt install netwtop
netwtop --version
netwtop --help
man netwtop
sudo netwtop
```

检查安装文件归属：

```sh
dpkg-query -W -f='${Package} ${Version} ${Status}\n' netwtop
dpkg -L netwtop
dpkg -V netwtop
```

从客户端移除 PPA 配置：

```sh
sudo add-apt-repository --remove "$NETWTOP_PPA"
sudo apt update
```

该操作只移除软件源，不会自动卸载已经安装的 `netwtop`。

## 12. 发布后记录

每次正式发布至少记录：

- Git commit 和 tag；
- upstream version 和完整 Debian/PPA version；
- 目标 Ubuntu series；
- `_source.changes` 和 `.dsc` 的 SHA-256；
- Launchpad source/build/publish 状态；
- 构建日志链接；
- 安装测试系统版本和测试结果。

生成本地摘要：

```sh
sha256sum \
    "$NETWTOP_PARENT/netwtop_${NETWTOP_PPA_VERSION}.dsc" \
    "$NETWTOP_CHANGES"
git rev-parse HEAD
git describe --tags --always --dirty
```

## 13. 后续版本的版本规则

Launchpad archive 接受过的版本号不能重复使用，即使对应包随后被删除也不应
重新上传同一版本。

### 13.1 同一上游版本的打包修订

修改 Debian 打包但不修改上游源码时：

```text
0.1.1-1~ppa2~ubuntu22.04.1
0.1.1-1~ppa3~ubuntu22.04.1
```

由于 PPA 已经保存 `netwtop_0.1.1.orig.tar.gz`，后续同一 upstream version
通常使用：

```sh
debuild -S -sd -k"$NETWTOP_KEY"
```

### 13.2 新的上游版本

例如发布 `0.1.2`：

```text
0.1.2-1~ppa1~ubuntu22.04.1
```

新 upstream version 需要新的 orig tarball，首次上传重新使用 `-sa`：

```sh
debuild -S -sa -k"$NETWTOP_KEY"
```

### 13.3 支持多个 Ubuntu series

不同 series 必须使用不同的完整版本号：

```text
Ubuntu 22.04 Jammy: 0.1.2-1~ppa1~ubuntu22.04.1
Ubuntu 24.04 Noble: 0.1.2-1~ppa1~ubuntu24.04.1
```

同时把 `debian/changelog` 的 Distribution 分别设置为 `jammy` 或 `noble`。
即使 `Architecture: all`，也应分别验证每个 series 的依赖和运行行为。

## 14. 固定的日常发布步骤

每次发布依次执行：

1. 更新 `bin/netwtop` 中的上游版本、man page 和 `CHANGELOG.md`；
2. 运行 smoke tests、Shell 语法检查和 Lintian；
3. 提交并创建不可变 Git tag；
4. 为目标 Ubuntu series 创建唯一 PPA version；
5. 新 upstream version 生成新的 orig tarball；
6. 使用 `debuild -S` 构建并签名源码上传；
7. 使用 `dput -o` 和 `dput -s` 检查；
8. 正式 `dput` 上传；
9. 检查 Launchpad 构建日志和 Published 状态；
10. 在干净系统中通过 PPA 安装、升级和运行测试；
11. 记录哈希、构建链接和测试结果。

## 15. 常见故障

### 15.1 `clearsign failed: No secret key`

确认私钥存在并显式指定完整指纹：

```sh
gpg --list-secret-keys "$NETWTOP_KEY"
gpgconf --launch gpg-agent
export GPG_TTY="$(tty)"
debuild -S -sa -k"$NETWTOP_KEY"
```

### 15.2 Launchpad 报 signing key unknown

检查：

- 公钥是否已经发送到 `keyserver.ubuntu.com`；
- Launchpad 是否已经完成加密邮件确认；
- `debuild -k` 使用的指纹是否与 Launchpad 页面一致；
- Launchpad 账号是否拥有目标 PPA 的上传权限。

### 15.3 `Source/binary (mixed) uploads are not allowed`

说明构建了 mixed upload。重新执行：

```sh
debuild -S -sa -k"$NETWTOP_KEY"
```

并只上传 `_source.changes`。

### 15.4 `File ... orig.tar.gz already exists but has different contents`

同一 upstream version 使用了不同的 orig tarball。不要覆盖或重新制作已被
Launchpad 接受的归档。恢复首次上传使用的原始 tarball，或者发布新的
upstream version。

### 15.5 Version already exists

递增 `~ppaN~`，例如从 `~ppa1~` 改为 `~ppa2~`，更新 changelog 后重新构建。
不要删除包后复用旧版本号。

### 15.6 Wrong distribution 或 unsupported series

检查：

```sh
dpkg-parsechangelog -S Distribution
grep '^Distribution:' "$NETWTOP_CHANGES"
```

目标 series 必须仍受 Launchpad PPA 支持，并且 changelog 与上传目标一致。

### 15.7 DEPWAIT 或构建失败

打开 Launchpad build log，优先检查：

- `Build-Depends` 是否存在于目标 Ubuntu series；
- binary package 的 `Depends` 是否可解析；
- 构建过程是否意外访问网络；
- `debian/rules` 是否依赖工作区之外的文件；
- 文件是否遗漏在 orig tarball 或 `debian.tar` 中。

本地构建成功并不能保证 Launchpad 的干净构建环境一定成功，应以 Launchpad
build log 为准。

### 15.8 PPA 已发布但客户端找不到包

检查：

```sh
sudo apt update
apt-cache policy netwtop
apt-cache madison netwtop
```

同时确认 PPA 页面状态已经是 Published，而不是 Pending、Building 或
Successfully built but not yet published。首次 archive key 生成也可能导致
短暂延迟。

## 16. 权限和安全边界

本地源码构建、签名和 `dput` 上传不应使用 root。只有以下操作通常需要
`sudo`：

- 安装或卸载系统软件包；
- 添加或移除客户端 PPA；
- 在系统范围验证安装结果。

维护者应当：

- 为源码上传密钥设置强 passphrase；
- 不提交 `.gnupg`、私钥、解密邮件或临时凭据；
- 不在 CI 日志中输出私钥；
- 定期检查密钥有效期；
- 丢失密钥控制权时立即撤销密钥，并在 Launchpad 更新有效上传密钥；
- 为 PPA 中的软件包持续提供缺陷和安全更新。

## 17. 官方参考资料

- [Personal Package Archive](https://documentation.ubuntu.com/launchpad/user/reference/packaging/ppas/ppa/)
- [Import an OpenPGP key](https://documentation.ubuntu.com/launchpad/user/how-to/import-openpgp-key/)
- [Upload a package to a PPA](https://documentation.ubuntu.com/launchpad/user/how-to/packaging/ppa-package-upload/)
- [Build a source package](https://documentation.ubuntu.com/launchpad/user/reference/packaging/ppas/building-a-source-package/)
- [Troubleshoot package upload errors](https://documentation.ubuntu.com/launchpad/user/explanation/packaging/package-upload-errors/)
- [Install a PPA](https://documentation.ubuntu.com/launchpad/user/how-to/packaging/ppa-install/)
- [Ubuntu package versioning](https://documentation.ubuntu.com/launchpad/user/reference/packaging/ppas/copying-packages/)
