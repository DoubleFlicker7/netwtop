# 通过 APT 安装 netwtop

本文档说明如何把当前 `netwtop` 项目发布为 Debian 软件包，并最终实现：

```sh
sudo apt update
sudo apt install netwtop
```

## 1. 先区分三种目标

生成一个 `.deb` 文件和实现直接通过包名安装并不是同一件事。

| 目标 | 用户执行的命令 | 是否需要软件仓库 |
| --- | --- | --- |
| 安装本地软件包 | `sudo apt install ./netwtop_0.1.0-1_all.deb` | 否 |
| 从项目自己的仓库安装 | 添加一次项目仓库，然后执行 `sudo apt install netwtop` | 是，自建仓库或 PPA |
| 从系统默认仓库安装 | `sudo apt install netwtop` | 是，必须进入 Debian/Ubuntu 官方仓库 |

如果希望用户在一台标准 Debian 或 Ubuntu 机器上不添加任何第三方源就能
安装，必须完成 Debian/Ubuntu 官方收录流程。

## 2. 发布前需要补齐的上游信息

### 2.1 开源许可证

项目必须明确以下信息：

- 版权持有人姓名或组织名称。
- 版权年份。
- 许可证，例如 MIT、Apache-2.0 或 GPL-3.0。
- 引用或修改的第三方代码及其许可证。

项目根目录已经提供：

```text
LICENSE
```

Debian 打包目录中还需要：

```text
debian/copyright
```

许可证必须由项目版权持有人决定。没有明确许可证时，不适合向 Debian
官方仓库提交软件包。

### 2.2 版本与正式发布

项目已经提供 `CHANGELOG.md`，发布前还应补齐以下版本机制：

- 增加 `VERSION` 文件，例如 `0.1.0`。
- 增加 `netwtop --version`。
- 在每次发布前把 `CHANGELOG.md` 的 Unreleased 内容归档到对应版本。
- 使用 Git 管理项目。
- 创建版本标签，例如 `v0.1.0`。
- 发布对应的源码归档，例如 `netwtop_0.1.0.orig.tar.gz`。
- 提供稳定的项目主页、源码仓库和问题反馈地址。

Debian 首次打包版本通常写成：

```text
0.1.0-1
```

`0.1.0` 是上游版本，`-1` 是 Debian 打包修订号。

### 2.3 man page

应增加：

```text
man/netwtop.1
```

安装后用户可以执行：

```sh
man netwtop
```

手册建议包含：

- `NAME`
- `SYNOPSIS`
- `DESCRIPTION`
- `OPTIONS`
- `INTERACTIVE KEYS`
- `OUTPUT FORMATS`
- `PRIVILEGES`
- `FILES`
- `EXAMPLES`
- `LIMITATIONS`
- `SEE ALSO`

`netwtop` 是普通用户命令，因此使用 man page 第 1 节。

## 3. 创建 Debian 打包目录

建议在项目根目录增加：

```text
debian/
├── changelog
├── control
├── copyright
├── docs
├── install
├── rules
├── source/
│   └── format
├── tests/
│   └── control
├── upstream/
│   └── metadata
└── watch
```

各文件职责如下：

| 文件 | 作用 |
| --- | --- |
| `debian/control` | 源码包、二进制包、依赖、维护者和描述。 |
| `debian/changelog` | Debian 版本历史、目标发行版和发布日期。 |
| `debian/copyright` | 上游及打包文件的版权和许可证。 |
| `debian/rules` | 由 debhelper 调用的构建、测试和安装入口。 |
| `debian/install` | 把项目文件映射到软件包文件系统。 |
| `debian/docs` | 安装到 `/usr/share/doc/netwtop/` 的文档。 |
| `debian/source/format` | 源码包格式，通常使用 `3.0 (quilt)`。 |
| `debian/watch` | 检查项目是否发布了新的上游版本。 |
| `debian/tests/control` | autopkgtest 的安装后测试配置。 |
| `debian/upstream/metadata` | 上游仓库、问题跟踪和文档元数据。 |

## 4. 定义软件包安装路径

源码按职责保存在 `src/`，打包时映射到标准安装目录：

```text
bin/netwtop
    → /usr/bin/netwtop

src/*
    → /usr/lib/netwtop/*

man/netwtop.1
    → /usr/share/man/man1/netwtop.1

README.md
    → /usr/share/doc/netwtop/README.md
```

以下开发文件通常不需要安装：

- 根目录的开发启动器 `netwtop`。
- `tests/` 和测试 fixture。
- `docs/DEVELOPMENT.md`，除非希望把开发文档也放入二进制包。

安装后的 `/usr/bin/netwtop` 会从 `/usr/lib/netwtop/manifest.sh` 读取模块
清单，并按清单顺序从 `/usr/lib/netwtop` 加载模块。

## 5. 编写 debian/control

初始配置可以参考：

```debcontrol
Source: netwtop
Section: net
Priority: optional
Maintainer: Your Name <your-email@example.com>
Build-Depends:
 debhelper-compat (= 13),
 iproute2,
 procps
Standards-Version: 4.7.4.1
Rules-Requires-Root: no
Homepage: https://example.com/netwtop
Vcs-Git: https://example.com/netwtop.git
Vcs-Browser: https://example.com/netwtop

Package: netwtop
Architecture: all
Depends:
 ${misc:Depends},
 iproute2,
 procps,
 mawk | gawk
Description: interactive per-user network traffic monitor
 netwtop displays interface, user, and command-level network usage
 in a responsive terminal interface.
```

依赖含义：

- `iproute2`：提供 Linux 后端所需的 `ss`。
- `procps`：提供 `ps`。
- `mawk | gawk`：提供 AWK 实现。
- `debhelper-compat (= 13)`：提供现代 Debian 构建流程。
- `${misc:Depends}`：由 debhelper 自动计算的通用依赖。

`netwtop` 是 Shell/AWK 程序，不包含 CPU 架构相关二进制，因此可以使用
`Architecture: all`。最终依赖必须在干净的 Debian 和 Ubuntu 环境中重新
验证。

## 6. 编写构建与安装规则

`debian/rules` 可以从最小 debhelper 配置开始：

```make
#!/usr/bin/make -f

%:
	dh $@

override_dh_auto_test:
	./tests/smoke.sh
```

并确保文件可执行：

```sh
chmod 755 debian/rules
```

`debian/install` 可以参考：

```text
bin/netwtop usr/bin
src/manifest.sh usr/lib/netwtop
src/runtime/*.sh usr/lib/netwtop/runtime
src/core/*.sh usr/lib/netwtop/core
src/backends/*.sh usr/lib/netwtop/backends
src/output/*.sh usr/lib/netwtop/output
src/ui/* usr/lib/netwtop/ui
man/netwtop.1 usr/share/man/man1
```

`debian/docs` 可以包含：

```text
README.md
docs/ARCHITECTURE.md
```

`debian/source/format` 内容为：

```text
3.0 (quilt)
```

## 7. 构建软件包

在 Debian/Ubuntu 开发环境中安装打包工具：

```sh
sudo apt install \
    build-essential \
    debhelper \
    devscripts \
    lintian \
    sbuild \
    autopkgtest
```

构建二进制包和源码包：

```sh
dpkg-buildpackage -us -uc
```

构建成功后，上级目录通常会出现：

```text
netwtop_0.1.0-1_all.deb
netwtop_0.1.0-1.dsc
netwtop_0.1.0-1.debian.tar.xz
netwtop_0.1.0-1_amd64.buildinfo
netwtop_0.1.0-1_amd64.changes
netwtop_0.1.0.orig.tar.gz
```

虽然二进制包是 `Architecture: all`，`.changes` 和 `.buildinfo` 文件名仍可能
包含执行构建的主机架构。

本地安装测试：

```sh
sudo apt install ./netwtop_0.1.0-1_all.deb
netwtop --help
netwtop --version
man netwtop
```

卸载测试：

```sh
sudo apt remove netwtop
```

## 8. 质量检查

至少执行：

```sh
lintian ../netwtop_0.1.0-1_amd64.changes
autopkgtest ../netwtop_0.1.0-1_all.deb -- null
```

建议增加：

- 使用 `sbuild` 在干净的 Debian chroot 中构建。
- 在 Debian stable、testing 和 unstable 中测试。
- 在支持的 Ubuntu LTS 版本中测试。
- 检查安装、升级、降级和卸载。
- 检查普通用户启动。
- 检查 root 跨用户命令归属。
- 运行 `shellcheck`。
- 检查可复现构建。
- 确认包中没有临时文件、测试输出或本地路径。

现有 `tests/smoke.sh` 可以由 `debian/rules` 和 autopkgtest 共同调用。
autopkgtest 还应验证已安装路径，而不仅是源码树中的开发入口。

## 9. 发布路线一：只发布 .deb

这是工作量最小的方式。

可以在 GitHub/GitLab Release 中提供：

```text
netwtop_0.1.0-1_all.deb
SHA256SUMS
SHA256SUMS.asc
```

用户安装方式为：

```sh
sudo apt install ./netwtop_0.1.0-1_all.deb
```

这种方式不能让新用户直接执行 `apt install netwtop`，因为 APT 不知道应该
从哪里查找该包。

## 10. 发布路线二：自建 APT 仓库

自建仓库可以实现“添加一次软件源，以后通过包名安装和升级”。

完整的仓库规划、GPG 密钥、`reprepro` 配置、HTTPS 部署、deb822
`.sources`、CI/CD 和密钥轮换步骤见
[自建 APT 仓库实施指南](SELF_HOSTED_APT_REPOSITORY.md)。本节只保留三种
发布路线之间的概览对比。

需要完成：

1. 构建 `.deb` 和源码包。
2. 为每个发行版维护 suite，例如 Debian trixie 或 Ubuntu noble。
3. 生成 `Packages`、`Packages.gz`、`Release` 和 `InRelease`。
4. 使用项目 GPG 密钥签名仓库元数据。
5. 通过 HTTPS 托管仓库。
6. 提供 `/etc/apt/keyrings/` 公钥安装说明。
7. 提供 deb822 `.sources` 文件。
8. 在每次发布时自动更新索引和签名。

常见仓库方案包括：

- `reprepro`
- `aptly`
- Launchpad PPA
- packagecloud
- GitHub Pages 配合 APT 仓库生成工具

用户首次需要添加仓库，之后即可执行：

```sh
sudo apt update
sudo apt install netwtop
sudo apt upgrade
```

仓库维护者还需要负责：

- GPG 密钥轮换和备份。
- HTTPS 域名和证书。
- 旧发行版支持周期。
- 软件包撤回与安全更新。
- 不同 Debian/Ubuntu 版本的依赖兼容性。

## 11. 发布路线三：进入 Debian 官方仓库

如果希望 Debian 用户无需添加第三方源就能安装，需要完成官方收录流程。

### 11.1 检查包名

在提交前重新检查以下位置：

- Debian Packages
- Debian Package Tracker
- Debian Sources
- WNPP

确认 `netwtop` 没有被其他源码包或二进制包占用，也没有其他维护者已经提交
同名 ITP。

### 11.2 提交 ITP

对于 Debian 中不存在的新软件包，先向 WNPP 提交 ITP：

```text
ITP: netwtop -- interactive per-user network traffic monitor
```

ITP 应说明：

- 软件用途。
- 上游主页。
- 源码仓库。
- 许可证。
- 计划维护者。
- 为什么适合进入 Debian。
- 是否由某个 Debian Team 协作维护。

### 11.3 构建并签名源码包

正式上传必须使用维护者的 OpenPGP 密钥签名。构建前需要确保：

- `debian/changelog` 的发行版字段正确。
- 源码包包含干净的上游归档。
- lintian 没有未解释的严重问题。
- 可以在干净环境中构建。
- autopkgtest 通过。

### 11.4 上传 mentors.debian.net

如果维护者不是 Debian Developer，通常先把签名后的源码包上传到
`mentors.debian.net`，然后提交 RFS（Request For Sponsorship）。

RFS 需要提供：

- 软件包下载地址。
- ITP Bug 编号。
- 当前版本。
- lintian 状态。
- 构建与测试结果。
- 对审阅者需要重点检查内容的说明。

### 11.5 Sponsor 和 NEW queue

Debian Developer 会审阅软件包并提出修改意见。审阅通过后由 Sponsor 代表
维护者上传。

首次进入 Debian 的包需要经过 NEW queue 人工审核，重点包括：

- 包名与描述。
- 版权与许可证。
- 源码完整性。
- 依赖和文件布局。
- 是否符合 Debian Policy。
- 是否适合进入目标 archive area。

被接受后通常先进入 Debian unstable，再根据测试和依赖状态迁移到 testing。
它不会自动出现在已经发布的 Debian stable 中；旧稳定版通常还需要
backports。

## 12. Ubuntu 安装范围

进入 Debian 并不意味着所有 Ubuntu 版本立即可用。

- Ubuntu 开发版本可能在同步窗口内从 Debian 自动同步。
- 已发布的 Ubuntu LTS 不会因此自动增加新包。
- 为现有 Ubuntu 版本提供包时，通常需要 Launchpad PPA 或单独申请进入
  Ubuntu/backports。
- 每个 Ubuntu series 都需要独立构建和依赖测试。

如果近期目标主要是 Ubuntu 用户，Launchpad PPA 通常比等待 Debian 包进入
Ubuntu 稳定版更快。

## 13. 推荐实施顺序

### 阶段一：建立可重复构建的 Debian 包

1. 确定许可证、版权持有人和维护者邮箱。
2. 确定首个版本号。
3. 增加 `--version` 和 `VERSION`，并从 `CHANGELOG.md` 确认发布内容。
4. 增加 `man/netwtop.1`。
5. 创建 `debian/` 目录。
6. 构建 `.deb` 和源码包。
7. 通过 lintian、sbuild 和 autopkgtest。
8. 发布签名的 `.deb` 和源码归档。

完成这一阶段后，可使用：

```sh
sudo apt install ./netwtop_0.1.0-1_all.deb
```

### 阶段二：建立项目 APT 仓库

1. 选择 reprepro、aptly、PPA 或托管服务。
2. 创建并保护仓库签名密钥。
3. 建立 Debian/Ubuntu 多发行版构建。
4. 自动发布仓库索引和签名。
5. 编写添加仓库的安装说明。

完成后，用户添加一次软件源即可使用：

```sh
sudo apt install netwtop
```

### 阶段三：提交 Debian 官方仓库

1. 检查包名和 WNPP。
2. 提交 ITP。
3. 上传 mentors。
4. 提交 RFS。
5. 根据 Sponsor 意见修改。
6. 等待 NEW queue 审核。
7. 维护后续版本、安全问题和 Debian Bug。

官方审核耗时不可预测，应与自建仓库并行，而不是阻塞用户获取软件包。

## 14. 开始打包前需要确定的信息

以下信息不能由打包工具自动决定：

- 项目许可证。
- 版权持有人和版权年份。
- Debian Maintainer 姓名及邮箱。
- 首个正式版本号。
- 项目主页。
- 公开 Git 仓库地址。
- Bug Tracker 地址。
- GPG 签名密钥。
- 优先支持的 Debian/Ubuntu 版本。

这些信息确定后，即可开始创建 `VERSION`、man page 和 `debian/` 打包文件。

## 15. 官方参考资料

- [Debian Policy Manual](https://www.debian.org/doc/debian-policy/)
- [Guide for Debian Maintainers](https://www.debian.org/doc/manuals/debmake-doc/)
- [Debian Mentors: Introduction for Maintainers](https://mentors.debian.net/intro-maintainers/)
- [Debian Mentors: Sponsoring Process](https://mentors.debian.net/sponsors/)
- [Debian Mentors: RFS How-To](https://mentors.debian.net/sponsors/rfs-howto/)
- [Debian Manpages](https://manpages.debian.org/)
