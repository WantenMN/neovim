# Fork 维护手册（release_fork）

`release_fork = 上游 master + fork-only 提交`：目前只有 nix 可复现构建
（`flake.nix` / `flake.lock`）+ CI（cachix-fork.yml）+ 本手册 + 同步脚本，
无代码分叉。日常只有一种操作：**跟进上游**（rebase，保持线性）。

## Fork-only 文件（rebase 时保留）

* `flake.nix` / `flake.lock`：fork 复现构建，上游没有此文件。
  `flake.nix` 用 nixpkgs 的 `neovim-unwrapped` recipe，
  `src` 替换为本树（即 master 快照），再经 `wrapNeovim`
  （见 nixpkgs `pkgs/applications/editors/neovim/wrapper.nix`）包一层。
  `src` 用 `lib.fileset.toSource` 排除 fork-only 文件
  （`flake.*` / `FORK.md` / `sync-upstream.sh` / 整个 `.github`），
  而不是裸 `src = self`：裸 `self` 在 CI（本地 checkout）和消费侧
  （github tarball）会算出不同的 store 路径，同 commit 却不同哈希，
  系统侧永远命中不了缓存、每次都本地重编。fileset 只 hash 真正源码，
  两边一致才能像 niri/helix 一样直接下载。代价是改 fork-only 文件
  不触发重建（CI 空跑命中缓存，属期望行为）。
  另带一个兼容垫片：上游在 0.12.5 之后把
  `runtime/nvim.desktop` 改名为 `org.neovim.nvim.desktop`，
  但 nixpkgs 的 `wrapper.nix` 仍硬编码 `rm + substitute nvim.desktop`；
  `flake.nix` 在 unwrapped 的 `postInstall` 里给旧路径建了同名 symlink，
  wrapper 无需改动即可在 master 上工作。若 nixpkgs 上游修了 wrapper
  （改用新文件名或 `rm -f`），可删掉该垫片。
  rebase 若提示冲突（上游将来某天加了自己的 flake），保留我方文件，
  手动合并上游意图。
* `.github/workflows/cachix-fork.yml`：release_fork 专属构建推送，上游没有此文件。
  上游重型 CI（`test.yml` / `test_bsd.yml` / `test_wasm.yml`）只在
  `master` / `release-*` push 时跑，release_fork push 不会触发，无需
  `branches-ignore`（niri 那边需要是因为它的 `ci.yml` 全分支跑）。
* `FORK.md` / `sync-upstream.sh`：本手册与同步脚本，上游没有。

## 0. 一键同步（推荐）

```bash
./sync-upstream.sh
```

脚本会：检查分支干净 → 加 `upstream`（没有的话）→ fetch →
rebase 到 `upstream/master`。
**它从不 push**：看完结果自己手动推。

推完等 CI 绿，nixos 侧 `nix flake update neovim` + 重建验证（第 3 节）。

本 clone 的 `origin` 是上游（`neovim/neovim`），fork 挂在 `fork`
（`WantenMN/neovim`），所以推送目标是 `fork`：

```bash
git push --force-with-lease fork release_fork
```

（若你的 clone 是 `origin = fork` 的布局，则照常 `git push
--force-with-lease origin release_fork`。）

## 1. 手动步骤（脚本做的事，拆开看）

```bash
git remote add upstream https://github.com/neovim/neovim.git  # 一次性
git remote add fork git@github.com:WantenMN/neovim.git        # 一次性（本机已配）
git fetch upstream
git checkout release_fork
git rebase upstream/master     # 冲突则 git rebase --abort，分支不动
```

## 2. 版本号：什么时候必须改 `flake.nix`

`flake.nix` 里 `version = "0.13.0-dev"` 必须与 `CMakeLists.txt` 的
`NVIM_VERSION_MAJOR/MINOR/PATCH/PRERELEASE` 一致。
目前上游是 `0.13.0-dev`。

**只有**上游改了 `CMakeLists.txt` 里这四个变量之一时（大版本 bump），
才需要同步改 `flake.nix` 的 `version`。其他任何更新（C 代码、runtime、
vim-patch）都不用动，`src` 变化会自动触发重建。

检查：

```bash
grep -n "NVIM_VERSION_" CMakeLists.txt
grep -n 'version = ' flake.nix
```

故意保持 `version` 稳定（不加 per-commit 后缀）：nixpkgs 的
treesitter grammars 按 `"neovim-${version}"` 打版本，version 稳定则
grammars  derivation 不变、CI 命中缓存；只有 nvim 本体随 `src` 重建。
若每个提交都改 version，每次 CI 都要重建全部 grammars，浪费时间。

## 3. nixos 侧验证（冷机等价）

```bash
nix flake update neovim   # dotfiles/nixos 下
NVIM=$(readlink -f $(which nvim))
nix path-info --store https://wanten.cachix.org "$NVIM"   # 打印路径 = 在缓存里
for p in $(nix-store -qR $NVIM); do
  nix path-info --store https://wanten.cachix.org "$p" >/dev/null 2>&1 && continue
  nix path-info --store https://cache.nixos.org "$p" >/dev/null 2>&1 && continue
  echo "MISS $p"
done
```

无 MISS = 任意冷机纯下载可用。`nvim --version` 应显示
`v0.13.0-dev`（+ build 信息），nix 侧 `nix build` 的输出路径即 pinned 路径。

nixpkgs 对齐说明：本 fork 不用 `inputs.nixpkgs.follows`，
CI 用自己的 lock standalone 构建，消费侧直接用
`inputs.neovim.packages` 保证 store 路径与缓存一致。
neovim 不像 niri 那样 `dlopen /run/opengl-driver`，无 glibc 跨代黑屏问题，
无需强制与系统同 glibc 时代；但仍建议 glibc 换代时顺手
`nix flake update nixpkgs` 一次，减少系统与 fork 的重复依赖下载。

## 4. 排错

* `cachix push` 报 `Nothing to push` 且构建失败 → 看完整日志找第一个
  `error: Cannot build`（`pipefail` 已开，这种情况 CI 会直接红）。
* nixpkgs 的 `system_rplugin_manifest.patch` 合不上（上游改了相关文件）→
  CI 会在 `patchPhase` 红，需跟进 nixpkgs 新版 patch 或临时去掉
  `patches`（先看 `pkgs/by-name/ne/neovim-unwrapped/package.nix` 的改动）。
* CI 磁盘不足 → `Free Disk Space` 步骤已加，一般不用动。
* rebase 冲突（极少，fork-only 文件与上游同名时）→
  `git rebase --abort`，分支不动，手动处理后再试。
  fork-only 文件为 `flake.nix` / `flake.lock` /
  `.github/workflows/cachix-fork.yml` / `FORK.md` / `sync-upstream.sh`，
  上游一般不会碰这些路径（除了未来可能加自己的 flake）。
