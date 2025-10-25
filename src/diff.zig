//! Diff view for AI-suggested changes
//! Show side-by-side comparison and allow accept/reject
const std = @import("std");

/// Diff change type
pub const ChangeType = enum {
    added,
    removed,
    modified,
    unchanged,
};

/// Diff hunk (a section of changes)
pub const DiffHunk = struct {
    old_start: u32,
    old_count: u32,
    new_start: u32,
    new_count: u32,
    lines: std.ArrayList(DiffLine),

    pub fn init(allocator: std.mem.Allocator) DiffHunk {
        return .{
            .old_start = 0,
            .old_count = 0,
            .new_start = 0,
            .new_count = 0,
            .lines = std.ArrayList(DiffLine).init(allocator),
        };
    }

    pub fn deinit(self: *DiffHunk) void {
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.deinit();
    }
};

/// Single line in diff
pub const DiffLine = struct {
    change_type: ChangeType,
    old_line_no: ?u32 = null,
    new_line_no: ?u32 = null,
    content: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DiffLine) void {
        self.allocator.free(self.content);
    }
};

/// Diff result
pub const Diff = struct {
    old_file: []const u8,
    new_file: []const u8,
    hunks: std.ArrayList(DiffHunk),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, old_file: []const u8, new_file: []const u8) !Diff {
        return .{
            .old_file = try allocator.dupe(u8, old_file),
            .new_file = try allocator.dupe(u8, new_file),
            .hunks = std.ArrayList(DiffHunk).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Diff) void {
        self.allocator.free(self.old_file);
        self.allocator.free(self.new_file);
        for (self.hunks.items) |*hunk| {
            hunk.deinit();
        }
        self.hunks.deinit();
    }

    /// Generate unified diff format
    pub fn toUnifiedDiff(self: *const Diff) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        const writer = result.writer();

        try writer.print("--- {s}\n", .{self.old_file});
        try writer.print("+++ {s}\n", .{self.new_file});

        for (self.hunks.items) |hunk| {
            try writer.print("@@ -{d},{d} +{d},{d} @@\n", .{
                hunk.old_start,
                hunk.old_count,
                hunk.new_start,
                hunk.new_count,
            });

            for (hunk.lines.items) |line| {
                const prefix: u8 = switch (line.change_type) {
                    .added => '+',
                    .removed => '-',
                    .modified => '!',
                    .unchanged => ' ',
                };
                try writer.print("{c}{s}\n", .{ prefix, line.content });
            }
        }

        return try result.toOwnedSlice();
    }
};

/// Diff generator (simple line-by-line comparison)
pub const DiffGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DiffGenerator {
        return .{ .allocator = allocator };
    }

    /// Generate diff between two texts
    pub fn generateDiff(
        self: *DiffGenerator,
        old_text: []const u8,
        new_text: []const u8,
        old_file: []const u8,
        new_file: []const u8,
    ) !Diff {
        var diff = try Diff.init(self.allocator, old_file, new_file);
        errdefer diff.deinit();

        // Split into lines
        var old_lines = std.mem.split(u8, old_text, "\n");
        var new_lines = std.mem.split(u8, new_text, "\n");

        var old_line_list = std.ArrayList([]const u8).init(self.allocator);
        defer old_line_list.deinit();
        var new_line_list = std.ArrayList([]const u8).init(self.allocator);
        defer new_line_list.deinit();

        while (old_lines.next()) |line| {
            try old_line_list.append(line);
        }
        while (new_lines.next()) |line| {
            try new_line_list.append(line);
        }

        // Simple line-by-line diff (can be improved with LCS algorithm)
        var hunk = DiffHunk.init(self.allocator);
        hunk.old_start = 1;
        hunk.new_start = 1;

        const max_lines = @max(old_line_list.items.len, new_line_list.items.len);

        for (0..max_lines) |i| {
            if (i < old_line_list.items.len and i < new_line_list.items.len) {
                const old_line = old_line_list.items[i];
                const new_line = new_line_list.items[i];

                if (std.mem.eql(u8, old_line, new_line)) {
                    // Unchanged
                    try hunk.lines.append(.{
                        .change_type = .unchanged,
                        .old_line_no = @intCast(i + 1),
                        .new_line_no = @intCast(i + 1),
                        .content = try self.allocator.dupe(u8, old_line),
                        .allocator = self.allocator,
                    });
                } else {
                    // Modified
                    try hunk.lines.append(.{
                        .change_type = .removed,
                        .old_line_no = @intCast(i + 1),
                        .content = try self.allocator.dupe(u8, old_line),
                        .allocator = self.allocator,
                    });
                    try hunk.lines.append(.{
                        .change_type = .added,
                        .new_line_no = @intCast(i + 1),
                        .content = try self.allocator.dupe(u8, new_line),
                        .allocator = self.allocator,
                    });
                }
            } else if (i < old_line_list.items.len) {
                // Line removed
                try hunk.lines.append(.{
                    .change_type = .removed,
                    .old_line_no = @intCast(i + 1),
                    .content = try self.allocator.dupe(u8, old_line_list.items[i]),
                    .allocator = self.allocator,
                });
            } else if (i < new_line_list.items.len) {
                // Line added
                try hunk.lines.append(.{
                    .change_type = .added,
                    .new_line_no = @intCast(i + 1),
                    .content = try self.allocator.dupe(u8, new_line_list.items[i]),
                    .allocator = self.allocator,
                });
            }
        }

        hunk.old_count = @intCast(old_line_list.items.len);
        hunk.new_count = @intCast(new_line_list.items.len);

        try diff.hunks.append(hunk);

        return diff;
    }
};

// Tests
test "generate simple diff" {
    var generator = DiffGenerator.init(std.testing.allocator);

    const old = "line1\nline2\nline3";
    const new = "line1\nmodified\nline3";

    var diff = try generator.generateDiff(old, new, "old.txt", "new.txt");
    defer diff.deinit();

    try std.testing.expectEqual(@as(usize, 1), diff.hunks.items.len);

    const unified = try diff.toUnifiedDiff();
    defer std.testing.allocator.free(unified);

    try std.testing.expect(std.mem.indexOf(u8, unified, "---") != null);
    try std.testing.expect(std.mem.indexOf(u8, unified, "+++") != null);
}
