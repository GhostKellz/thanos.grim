//! Selection tracking for AI context
//! Captures cursor position and visual selections for sending to AI
const std = @import("std");

/// Selection type
pub const SelectionType = enum {
    cursor, // Just cursor position (no selection)
    visual_char, // Character-wise visual selection
    visual_line, // Line-wise visual selection
    visual_block, // Block-wise visual selection
};

/// Position in buffer (0-indexed)
pub const Position = struct {
    line: u32,
    column: u32,
};

/// Selection range
pub const Selection = struct {
    type: SelectionType,
    start: Position,
    end: Position,
    text: []const u8, // Selected text (empty for cursor-only)
    file_path: []const u8,
    language: ?[]const u8 = null,

    /// Check if selection is empty (cursor only)
    pub fn isEmpty(self: *const Selection) bool {
        return self.text.len == 0;
    }

    /// Get selection as LSP-compatible range
    pub fn toLSPRange(self: *const Selection) struct {
        start: struct { line: u32, character: u32 },
        end: struct { line: u32, character: u32 },
    } {
        return .{
            .start = .{
                .line = self.start.line,
                .character = self.start.column,
            },
            .end = .{
                .line = self.end.line,
                .character = self.end.column,
            },
        };
    }

    pub fn deinit(self: *Selection, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        allocator.free(self.file_path);
        if (self.language) |lang| {
            allocator.free(lang);
        }
    }
};

/// Selection tracker
pub const SelectionTracker = struct {
    allocator: std.mem.Allocator,
    current_selection: ?Selection = null,
    last_update: i64 = 0,

    pub fn init(allocator: std.mem.Allocator) SelectionTracker {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SelectionTracker) void {
        if (self.current_selection) |*sel| {
            sel.deinit(self.allocator);
        }
    }

    /// Update current selection
    pub fn updateSelection(self: *SelectionTracker, selection: Selection) !void {
        // Free old selection
        if (self.current_selection) |*old_sel| {
            old_sel.deinit(self.allocator);
        }

        self.current_selection = selection;
        self.last_update = std.time.timestamp();
    }

    /// Get current selection (returns null if cursor only)
    pub fn getSelection(self: *const SelectionTracker) ?Selection {
        return self.current_selection;
    }

    /// Clear selection
    pub fn clearSelection(self: *SelectionTracker) void {
        if (self.current_selection) |*sel| {
            sel.deinit(self.allocator);
            self.current_selection = null;
        }
    }
};

/// Helper to extract selection from buffer
pub fn extractSelection(
    allocator: std.mem.Allocator,
    buffer_lines: []const []const u8,
    start_line: u32,
    start_col: u32,
    end_line: u32,
    end_col: u32,
    selection_type: SelectionType,
) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    if (start_line == end_line) {
        // Single line selection
        const line = buffer_lines[start_line];
        const start = @min(start_col, @as(u32, @intCast(line.len)));
        const end = @min(end_col, @as(u32, @intCast(line.len)));
        try result.appendSlice(line[start..end]);
    } else {
        // Multi-line selection
        switch (selection_type) {
            .visual_line => {
                // Include full lines
                for (start_line..end_line + 1) |i| {
                    try result.appendSlice(buffer_lines[i]);
                    if (i < end_line) {
                        try result.append('\n');
                    }
                }
            },
            .visual_char => {
                // First line (from start_col to end)
                const first_line = buffer_lines[start_line];
                try result.appendSlice(first_line[start_col..]);
                try result.append('\n');

                // Middle lines (full)
                for (start_line + 1..end_line) |i| {
                    try result.appendSlice(buffer_lines[i]);
                    try result.append('\n');
                }

                // Last line (from start to end_col)
                if (end_line < buffer_lines.len) {
                    const last_line = buffer_lines[end_line];
                    const end = @min(end_col, @as(u32, @intCast(last_line.len)));
                    try result.appendSlice(last_line[0..end]);
                }
            },
            .visual_block => {
                // Block selection (rectangular)
                const min_col = @min(start_col, end_col);
                const max_col = @max(start_col, end_col);

                for (start_line..end_line + 1) |i| {
                    const line = buffer_lines[i];
                    const start = @min(min_col, @as(u32, @intCast(line.len)));
                    const end = @min(max_col, @as(u32, @intCast(line.len)));
                    try result.appendSlice(line[start..end]);
                    if (i < end_line) {
                        try result.append('\n');
                    }
                }
            },
            .cursor => {}, // No text for cursor-only
        }
    }

    return try result.toOwnedSlice();
}

// Tests
test "extract single line selection" {
    const buffer = [_][]const u8{
        "line one",
        "line two",
        "line three",
    };

    const text = try extractSelection(
        std.testing.allocator,
        &buffer,
        1,
        5, // "two"
        1,
        8,
        .visual_char,
    );
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("two", text);
}

test "extract multi-line selection" {
    const buffer = [_][]const u8{
        "line one",
        "line two",
        "line three",
    };

    const text = try extractSelection(
        std.testing.allocator,
        &buffer,
        0,
        5, // "one"
        2,
        9, // to end of "three"
        .visual_char,
    );
    defer std.testing.allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "one") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "two") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "three") != null);
}

test "selection tracker" {
    var tracker = SelectionTracker.init(std.testing.allocator);
    defer tracker.deinit();

    // Initially no selection
    try std.testing.expect(tracker.getSelection() == null);

    // Add selection
    const selection = Selection{
        .type = .visual_char,
        .start = .{ .line = 0, .column = 0 },
        .end = .{ .line = 0, .column = 5 },
        .text = try std.testing.allocator.dupe(u8, "hello"),
        .file_path = try std.testing.allocator.dupe(u8, "test.zig"),
    };

    try tracker.updateSelection(selection);

    const current = tracker.getSelection().?;
    try std.testing.expectEqualStrings("hello", current.text);

    // Clear selection
    tracker.clearSelection();
    try std.testing.expect(tracker.getSelection() == null);
}
