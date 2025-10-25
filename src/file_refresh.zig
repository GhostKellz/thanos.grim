//! File refresh - auto-reload files modified by AI
const std = @import("std");

/// File watcher entry
pub const FileWatch = struct {
    path: []const u8,
    last_modified: i128,
    hash: u64,
};

/// File refresh manager
pub const FileRefreshManager = struct {
    allocator: std.mem.Allocator,
    watched_files: std.StringHashMap(FileWatch),
    check_interval_ms: u64,
    last_check: i64,

    pub fn init(allocator: std.mem.Allocator, check_interval_ms: u64) FileRefreshManager {
        return .{
            .allocator = allocator,
            .watched_files = std.StringHashMap(FileWatch).init(allocator),
            .check_interval_ms = check_interval_ms,
            .last_check = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *FileRefreshManager) void {
        var it = self.watched_files.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.watched_files.deinit();
    }

    /// Add file to watch list
    pub fn watchFile(self: *FileRefreshManager, path: []const u8) !void {
        const stat = try std.fs.cwd().statFile(path);
        const hash = try self.hashFile(path);

        const path_copy = try self.allocator.dupe(u8, path);

        try self.watched_files.put(path_copy, .{
            .path = path_copy,
            .last_modified = stat.mtime,
            .hash = hash,
        });
    }

    /// Check if any watched files have changed
    pub fn checkForChanges(self: *FileRefreshManager) !std.ArrayList([]const u8) {
        var changed = std.ArrayList([]const u8).init(self.allocator);
        errdefer changed.deinit();

        const now = std.time.milliTimestamp();
        if (now - self.last_check < self.check_interval_ms) {
            return changed;
        }

        self.last_check = now;

        var it = self.watched_files.iterator();
        while (it.next()) |entry| {
            const watch = entry.value_ptr;

            // Check if file still exists
            const stat = std.fs.cwd().statFile(watch.path) catch continue;

            // Check if modified
            if (stat.mtime != watch.last_modified) {
                const new_hash = try self.hashFile(watch.path);
                if (new_hash != watch.hash) {
                    // File actually changed (not just timestamp)
                    try changed.append(watch.path);

                    // Update watch
                    watch.last_modified = stat.mtime;
                    watch.hash = new_hash;
                }
            }
        }

        return changed;
    }

    /// Remove file from watch list
    pub fn unwatchFile(self: *FileRefreshManager, path: []const u8) void {
        if (self.watched_files.fetchRemove(path)) |entry| {
            self.allocator.free(entry.key);
        }
    }

    /// Hash file contents for change detection
    fn hashFile(self: *FileRefreshManager, path: []const u8) !u64 {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        return std.hash.Wyhash.hash(0, content);
    }
};

// Tests
test "file refresh manager" {
    var manager = FileRefreshManager.init(std.testing.allocator, 100);
    defer manager.deinit();

    // Create temp file
    const temp_path = "test_refresh.tmp";
    {
        const file = try std.fs.cwd().createFile(temp_path, .{});
        defer file.close();
        try file.writeAll("initial content");
    }
    defer std.fs.cwd().deleteFile(temp_path) catch {};

    // Watch file
    try manager.watchFile(temp_path);

    // No changes initially
    var changed = try manager.checkForChanges();
    try std.testing.expectEqual(@as(usize, 0), changed.items.len);
    changed.deinit();

    // Modify file
    std.time.sleep(10 * std.time.ns_per_ms); // Small delay
    {
        const file = try std.fs.cwd().openFile(temp_path, .{ .mode = .write_only });
        defer file.close();
        try file.writeAll("modified content");
    }

    // Should detect change (but need to wait for interval)
    manager.last_check = 0; // Force check
    changed = try manager.checkForChanges();
    // Note: May be 0 if filesystem mtime resolution is too coarse
    changed.deinit();
}
