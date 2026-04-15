# Rust 编译知识

## crate-type 类型

| 类型 | 说明 | 适用场景 |
|------|------|----------|
| `rlib` | Rust 静态库 | 链接到其他 Rust crate |
| `dylib` | Rust 动态库 | 运行时加载 |
| `staticlib` | C 静态库 | 与 C 代码链接 |
| `cdylib` | C 兼容动态库 | FFI 调用 |

## OpenHarmony 中的 crate_type 指定

**注意**: OpenHarmony 的 crate type **不是**在 Cargo.toml 中指定的，而是由 GN 模板决定：

```python
# build/templates/rust/rust_template.gni 第 328-337 行
template("ohos_rust_shared_library") {
  rust_target("$_target_name") {
    target_type = "ohos_rust_library"
    crate_type = "dylib"   # <-- 这里是硬编码
```

## "std only shows up once" 错误原因

Rust 编译器在链接时要求：
- 同一个 crate (如 std) 只能以一种格式出现
- 混合 rlib 和 dylib 格式会导致歧义
- 必须统一所有上游 crate 的格式

## 解决方案

注释掉 `build/templates/rust/rust_template.gni` 中的 `-Cprefer-dynamic` 标志：

```python
# if (!defined(rust_static_link) || !rust_static_link) {
#   rustflags += [ "-Cprefer-dynamic" ]
# }
```
