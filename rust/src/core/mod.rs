//! 短信应用的核心引擎（纯 Rust，不含 FFI）。
//!
//! 模块划分：
//! - `analysis`：正文分类、OTP 提取、链接提取
//! - `segment`：GSM-7 / UCS-2 分段计算
//! - `search`：内存倒排索引与 BM25-lite 排序
//! - `store`：数据目录、回收站、设置持久化
//! - `mms_pdu`：WAP-230/WSP M-Retrieve.conf 子集编解码
//! - `crypto`：X25519 + HKDF + AES-256-GCM 信封加密
//! - `utf16`：UTF-16 码元下标/切片工具（Dart 侧高亮使用）

pub mod analysis;
pub mod crypto;
pub mod mms_pdu;
pub mod search;
pub mod segment;
pub mod store;
pub mod utf16;
