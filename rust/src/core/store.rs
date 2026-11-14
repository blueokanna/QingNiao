
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use once_cell::sync::Lazy;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};

pub const TRASH_FILE: &str = "trash.json";
pub const SETTINGS_FILE: &str = "settings.json";

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TrashEntry {
    pub id: i64,
    pub thread_id: i64,
    pub address: String,
    pub body: String,
    pub date: i64,
    pub kind: i32,
    pub deleted_at: i64,
}

#[derive(Default)]
pub struct Store {
    dir: Option<PathBuf>,
    trash: Vec<TrashEntry>,
    settings: BTreeMap<String, String>,
}

impl Store {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn dir(&self) -> Option<&Path> {
        self.dir.as_deref()
    }

    pub fn init(&mut self, data_dir: &str) -> bool {
        let trimmed = data_dir.trim();
        if trimmed.is_empty() {
            return false;
        }
        let path = PathBuf::from(trimmed);
        if self.dir.as_ref() == Some(&path) {
            return true;
        }
        if fs::create_dir_all(&path).is_err() {
            return false;
        }
        self.trash = load_trash(&path);
        self.settings = load_settings(&path);
        self.dir = Some(path);
        true
    }

    pub fn settings_get(&self, key: &str) -> Option<String> {
        self.settings.get(key).cloned()
    }

    pub fn settings_set(&mut self, key: &str, value: &str) -> bool {
        if key.is_empty() || self.dir.is_none() {
            return false;
        }
        let previous = self.settings.insert(key.to_owned(), value.to_owned());
        if self.save_settings() {
            return true;
        }
        match previous {
            Some(old) => self.settings.insert(key.to_owned(), old),
            None => self.settings.remove(key),
        };
        false
    }

    pub fn trash_add(&mut self, entry: TrashEntry) -> bool {
        if self.dir.is_none() {
            return false;
        }
        let mut entry = entry;
        if entry.deleted_at <= 0 {
            entry.deleted_at = now_ms();
        }
        let snapshot = self.trash.clone();
        match self.trash.iter_mut().find(|existing| existing.id == entry.id) {
            Some(existing) => *existing = entry,
            None => self.trash.insert(0, entry),
        }
        if self.save_trash() {
            true
        } else {
            self.trash = snapshot;
            false
        }
    }

    pub fn trash_entries(&self) -> Vec<TrashEntry> {
        self.trash.clone()
    }

    pub fn trash_restore(&mut self, id: i64) -> bool {
        self.remove_entry(id)
    }

    pub fn trash_remove(&mut self, id: i64) -> bool {
        self.remove_entry(id)
    }

    fn remove_entry(&mut self, id: i64) -> bool {
        if self.dir.is_none() {
            return false;
        }
        let position = match self.trash.iter().position(|entry| entry.id == id) {
            Some(position) => position,
            None => return false,
        };
        let removed = self.trash.remove(position);
        if self.save_trash() {
            true
        } else {
            self.trash.insert(position.min(self.trash.len()), removed);
            false
        }
    }

    pub fn trash_purge(&mut self, retention_days: i32) -> u32 {
        self.trash_purge_at(now_ms(), retention_days)
    }

    pub fn trash_purge_at(&mut self, now: i64, retention_days: i32) -> u32 {
        if retention_days <= 0 || self.dir.is_none() {
            return 0;
        }
        let cutoff = now.saturating_sub(retention_days as i64 * 86_400_000);
        let snapshot = self.trash.clone();
        let before = self.trash.len();
        self.trash.retain(|entry| entry.deleted_at >= cutoff);
        let removed = before.saturating_sub(self.trash.len()) as u32;
        if removed == 0 {
            return 0;
        }
        if self.save_trash() {
            removed
        } else {
            self.trash = snapshot;
            0
        }
    }

    fn save_trash(&self) -> bool {
        match self.dir.as_ref() {
            Some(dir) => write_json_atomic(&dir.join(TRASH_FILE), &self.trash),
            None => false,
        }
    }

    fn save_settings(&self) -> bool {
        match self.dir.as_ref() {
            Some(dir) => write_json_atomic(&dir.join(SETTINGS_FILE), &self.settings),
            None => false,
        }
    }
}

static STORE: Lazy<Mutex<Store>> = Lazy::new(|| Mutex::new(Store::new()));

pub fn init(data_dir: &str) -> bool {
    STORE.lock().init(data_dir)
}

pub fn data_dir() -> Option<PathBuf> {
    STORE.lock().dir().map(|path| path.to_path_buf())
}

pub fn settings_get(key: &str) -> Option<String> {
    STORE.lock().settings_get(key)
}

pub fn settings_set(key: &str, value: &str) -> bool {
    STORE.lock().settings_set(key, value)
}

pub fn trash_add(entry: TrashEntry) -> bool {
    STORE.lock().trash_add(entry)
}

pub fn trash_entries() -> Vec<TrashEntry> {
    STORE.lock().trash_entries()
}

pub fn trash_restore(id: i64) -> bool {
    STORE.lock().trash_restore(id)
}

pub fn trash_remove(id: i64) -> bool {
    STORE.lock().trash_remove(id)
}

pub fn trash_purge(retention_days: i32) -> u32 {
    STORE.lock().trash_purge(retention_days)
}

pub fn reset() {
    *STORE.lock() = Store::new();
}

fn now_ms() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(duration) => duration.as_millis() as i64,
        Err(_) => 0,
    }
}

fn load_trash(dir: &Path) -> Vec<TrashEntry> {
    let path = dir.join(TRASH_FILE);
    let data = match fs::read(&path) {
        Ok(data) => data,
        Err(_) => return Vec::new(),
    };
    match serde_json::from_slice::<Vec<TrashEntry>>(&data) {
        Ok(entries) => dedupe_by_id(entries),
        Err(_) => {
            backup(&path);
            Vec::new()
        }
    }
}

fn load_settings(dir: &Path) -> BTreeMap<String, String> {
    let path = dir.join(SETTINGS_FILE);
    let data = match fs::read(&path) {
        Ok(data) => data,
        Err(_) => return BTreeMap::new(),
    };
    match serde_json::from_slice::<BTreeMap<String, String>>(&data) {
        Ok(settings) => settings,
        Err(_) => {
            backup(&path);
            BTreeMap::new()
        }
    }
}

fn dedupe_by_id(entries: Vec<TrashEntry>) -> Vec<TrashEntry> {
    let mut out: Vec<TrashEntry> = Vec::with_capacity(entries.len());
    for entry in entries {
        if out.iter().any(|existing| existing.id == entry.id) {
            continue;
        }
        out.push(entry);
    }
    out
}

fn backup(path: &Path) {
    let target = path.with_extension("json.bak");
    let _ = fs::copy(path, target);
}

fn write_json_atomic<T: Serialize>(path: &Path, value: &T) -> bool {
    let data = match serde_json::to_vec(value) {
        Ok(data) => data,
        Err(_) => return false,
    };
    let tmp = path.with_extension("json.tmp");
    if fs::write(&tmp, &data).is_err() {
        return false;
    }
    if fs::rename(&tmp, path).is_ok() {
        return true;
    }
    let _ = fs::remove_file(&tmp);
    fs::write(path, &data).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or(0);
        let dir = std::env::temp_dir().join(format!(
            "qingniao-store-{}-{}-{}",
            tag,
            std::process::id(),
            nanos
        ));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    fn entry(id: i64, body: &str) -> TrashEntry {
        TrashEntry {
            id,
            thread_id: id * 10,
            address: "10086".into(),
            body: body.into(),
            date: 1_600_000_000_000,
            kind: 0,
            deleted_at: 0,
        }
    }

    #[test]
    fn init_creates_directory_and_is_idempotent() {
        let dir = temp_dir("init");
        let mut store = Store::new();
        assert!(store.init(dir.to_str().unwrap()));
        assert!(dir.is_dir());
        assert!(store.init(dir.to_str().unwrap()));
        assert!(store.dir().is_some());
        assert!(!store.init("   "));

        let file = dir.join("blocked");
        fs::write(&file, b"x").unwrap();
        let mut other = Store::new();
        assert!(!other.init(file.to_str().unwrap()));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn trash_is_persisted_and_deduped() {
        let dir = temp_dir("trash");
        let mut store = Store::new();
        assert!(store.init(dir.to_str().unwrap()));
        assert!(store.trash_add(entry(1, "第一条")));
        assert!(store.trash_add(entry(2, "第二条")));
        assert!(store.trash_add(entry(1, "覆盖后的第一条")));
        let entries = store.trash_entries();
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].id, 2, "新加入的排在最前");
        assert_eq!(
            entries[1].body, "覆盖后的第一条",
            "同 id 就地覆盖，位置不变"
        );
        assert!(entries[1].deleted_at > 0);

        let mut reloaded = Store::new();
        assert!(reloaded.init(dir.to_str().unwrap()));
        assert_eq!(reloaded.trash_entries(), entries);

        assert!(!dir.join("trash.json.tmp").exists());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn restore_and_remove_persist() {
        let dir = temp_dir("restore");
        let mut store = Store::new();
        store.init(dir.to_str().unwrap());
        store.trash_add(entry(7, "待恢复"));
        store.trash_add(entry(8, "待删除"));

        assert!(store.trash_restore(7));
        assert!(!store.trash_restore(7));
        assert!(store.trash_remove(8));
        assert!(!store.trash_remove(8));

        let mut reloaded = Store::new();
        reloaded.init(dir.to_str().unwrap());
        assert!(reloaded.trash_entries().is_empty());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn purge_respects_retention() {
        let dir = temp_dir("purge");
        let mut store = Store::new();
        store.init(dir.to_str().unwrap());
        store.trash_add(entry(1, "旧"));
        store.trash_add(entry(2, "新"));

        let now = now_ms();
        assert_eq!(store.trash_purge_at(now + 10 * 86_400_000, 0), 0);
        assert_eq!(store.trash_purge_at(now + 10 * 86_400_000, -1), 0);
        assert_eq!(store.trash_entries().len(), 2);

        assert_eq!(store.trash_purge_at(now + 2 * 86_400_000, 1), 2);
        assert!(store.trash_entries().is_empty());

        let mut reloaded = Store::new();
        reloaded.init(dir.to_str().unwrap());
        assert!(reloaded.trash_entries().is_empty());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn purge_keeps_fresh_entries() {
        let dir = temp_dir("fresh");
        let mut store = Store::new();
        store.init(dir.to_str().unwrap());
        store.trash_add(entry(1, "刚刚删除"));
        assert_eq!(store.trash_purge(1), 0);
        assert_eq!(store.trash_entries().len(), 1);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn corrupt_files_fall_back_and_backup() {
        let dir = temp_dir("corrupt");
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join(TRASH_FILE), b"{ not json ").unwrap();
        fs::write(dir.join(SETTINGS_FILE), b"[[[").unwrap();

        let mut store = Store::new();
        assert!(store.init(dir.to_str().unwrap()));
        assert!(store.trash_entries().is_empty());
        assert!(store.settings_get("any").is_none());
        assert!(dir.join("trash.json.bak").exists());
        assert!(dir.join("settings.json.bak").exists());

        assert!(store.settings_set("theme", "dark"));
        let mut reloaded = Store::new();
        reloaded.init(dir.to_str().unwrap());
        assert_eq!(reloaded.settings_get("theme").as_deref(), Some("dark"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn settings_round_trip() {
        let dir = temp_dir("settings");
        let mut store = Store::new();
        assert!(!store.settings_set("k", "v"), "未初始化时不写入");
        assert!(store.init(dir.to_str().unwrap()));
        assert!(store.settings_set("retention_days", "30"));
        assert!(store.settings_set("中文键", "值🌿"));
        assert_eq!(store.settings_get("retention_days").as_deref(), Some("30"));
        assert_eq!(store.settings_get("中文键").as_deref(), Some("值🌿"));
        assert!(store.settings_get("missing").is_none());
        assert!(!store.settings_set("", "x"));

        let mut reloaded = Store::new();
        reloaded.init(dir.to_str().unwrap());
        assert_eq!(reloaded.settings_get("retention_days").as_deref(), Some("30"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn uninitialized_store_rejects_writes() {
        let mut store = Store::new();
        assert!(!store.trash_add(entry(1, "x")));
        assert!(!store.trash_restore(1));
        assert!(!store.trash_remove(1));
        assert_eq!(store.trash_purge(1), 0);
        assert!(store.trash_entries().is_empty());
    }
}
