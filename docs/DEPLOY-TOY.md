# 把网页前端挂到 B 站小玩具

游戏服留在杭州。小玩具只放 Godot 导出的静态页。

## 架构

| 部分 | 放哪 | 地址 |
|------|------|------|
| 网页 | B 站小玩具，或别的静态托管 | 页面域名不固定，常在子路径下 |
| 联机 | 杭州 `bomberman.jopatk.top` | `wss://bomberman.jopatk.top/ws` |

`Net.get_default_join_address()` 在网页导出里默认就是上面这条 WSS，不再用 `location.host` 拼地址。页面挂在 `bilibili.com/toy/…` 时，客户端仍然连杭州。

本机打开的页面（`localhost`、`127.0.0.1`、`::1`，可以带端口）仍连**当前主机**的 `/ws`，方便在自己电脑上用浏览器试。桌面客户端默认还是 `127.0.0.1:9080`。

Web 导出保持 `variant/thread_support=false`（`export_presets.cfg` 里已经关掉）。小玩具一般不会下发 COOP/COEP，开线程的导出会直接起不来。

这次只改客户端默认地址和打包。不要为了上小玩具去动杭州上的进程或 Nginx。

## 打包

先在构建机导出 Web：

```bash
godot --headless --path . --export-release "Web" build/web/index.html
./tools/pack_toy.sh
```

产物是 `build/toy/bomberman-toy.zip`。`build/` 已在 `.gitignore` 里，wasm 和 zip 不要提交。

脚本假定 `build/web/` 里已经有 `index.html`、`.js`、`.wasm`、`.pck`，然后：

1. 拷到 `build/toy/`。
2. 把 `index.html` 里以 `/` 开头的资源路径改成相对路径（去掉开头的那一个 `/`）。`//主机/…` 这种协议相对路径无法安全改写，脚本会失败。
3. 确认 `index.html` ≤ 1MB。
4. 打成 zip。压缩包**根目录**就是 `index.html`，不再套一层文件夹。小玩具按子路径打开页面时，相对路径才会落到包内文件上。

### `.pck` 改成 `.data`

默认保留 `.pck`。若后台白名单不收 `.pck`、只收 `.data`：

```bash
TOY_PCK_AS_DATA=1 ./tools/pack_toy.sh
```

Godot 4.7 的网页加载器使用 `mainPack`，没有则退回 `可执行名.pck`。脚本会：

- 把唯一的 `.pck` 改名为同名 `.data`
- 在 `index.html` 的 `GODOT_CONFIG` 里写上 `mainPack`
- 同步 `fileSizes` 里的文件名，以及其它文本里的同名引用

导出里有多于一个 `.pck` 时，这个开关会失败，避免写错主包。

## 先预览，再发布

上传 zip 之后，先用**仅链接可见的预览**，不要直接公开。用预览链接确认：

- 大厅能出来（脚本、wasm、pck 都从当前目录加载，而不是打到网站根上）
- 「高级」里的加入地址是 `wss://bomberman.jopatk.top/ws`
- 能进房间，并和杭州上的专用服打一局

确认后再发布。

## 回滚

小玩具页面出问题，就先下架，或把入口改回 `https://bomberman.jopatk.top/`——前提是杭州那台机器上还留着原来的静态页。联机地址本来就是同一条 WSS，游戏服不用重启，也不用为了回滚重新部署。
