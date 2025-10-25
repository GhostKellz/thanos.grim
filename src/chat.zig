//! Interactive AI Chat - Like Claude Code
//!
//! Multi-turn conversational interface with any AI provider
const std = @import("std");
const thanos = @import("thanos");

pub const ChatSession = struct {
    allocator: std.mem.Allocator,
    thanos_instance: *thanos.Thanos,
    messages: std.ArrayList(Message),
    current_provider: thanos.types.Provider,

    pub const Message = struct {
        role: []const u8, // "user" or "assistant"
        content: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, thanos_instance: *thanos.Thanos, provider: thanos.types.Provider) !ChatSession {
        return ChatSession{
            .allocator = allocator,
            .thanos_instance = thanos_instance,
            .messages = std.ArrayList(Message).init(allocator),
            .current_provider = provider,
        };
    }

    pub fn deinit(self: *ChatSession) void {
        for (self.messages.items) |msg| {
            self.allocator.free(msg.role);
            self.allocator.free(msg.content);
        }
        self.messages.deinit();
    }

    /// Send a message and get response
    pub fn sendMessage(self: *ChatSession, user_message: []const u8) ![]const u8 {
        // Add user message to history
        try self.messages.append(.{
            .role = try self.allocator.dupe(u8, "user"),
            .content = try self.allocator.dupe(u8, user_message),
        });

        // Build conversation context
        var context = std.ArrayList(u8).init(self.allocator);
        defer context.deinit();

        for (self.messages.items) |msg| {
            try context.appendSlice(msg.role);
            try context.appendSlice(": ");
            try context.appendSlice(msg.content);
            try context.appendSlice("\n\n");
        }

        try context.appendSlice("assistant: ");

        // Get completion from AI
        const request = thanos.types.CompletionRequest{
            .prompt = context.items,
            .provider = self.current_provider,
            .max_tokens = 4096,
            .temperature = 0.7,
            .system_prompt = "You are a helpful AI coding assistant. Provide clear, concise answers.",
        };

        const response = try self.thanos_instance.complete(request);

        if (!response.success) {
            return error.CompletionFailed;
        }

        // Add assistant response to history
        try self.messages.append(.{
            .role = try self.allocator.dupe(u8, "assistant"),
            .content = try self.allocator.dupe(u8, response.text),
        });

        return response.text;
    }

    /// Switch to a different provider
    pub fn switchProvider(self: *ChatSession, provider: thanos.types.Provider) void {
        self.current_provider = provider;
    }

    /// Clear conversation history
    pub fn clearHistory(self: *ChatSession) void {
        for (self.messages.items) |msg| {
            self.allocator.free(msg.role);
            self.allocator.free(msg.content);
        }
        self.messages.clearAndFree();
    }

    /// Get formatted history for display
    pub fn getHistory(self: *ChatSession) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();

        for (self.messages.items, 0..) |msg, i| {
            if (i > 0) try output.appendSlice("\n\n");

            if (std.mem.eql(u8, msg.role, "user")) {
                try output.appendSlice("You: ");
            } else {
                try output.appendSlice("AI: ");
            }
            try output.appendSlice(msg.content);
        }

        return output.toOwnedSlice();
    }
};

/// Simple CLI chat interface (for testing)
pub fn runChatCLI(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    // Load config
    const config = try thanos.config.loadConfig(allocator, "thanos.toml");
    defer config.deinit();

    // Initialize Thanos
    var ai = try thanos.Thanos.init(allocator, config);
    defer ai.deinit();

    // Create chat session (default to Anthropic)
    var chat = try ChatSession.init(allocator, &ai, .anthropic);
    defer chat.deinit();

    try stdout.print("🌌 Thanos AI Chat\n", .{});
    try stdout.print("Provider: {s}\n", .{@tagName(chat.current_provider)});
    try stdout.print("Commands: /help, /switch <provider>, /clear, /history, /quit\n\n", .{});

    var buffer: [4096]u8 = undefined;

    while (true) {
        try stdout.print("> ", .{});

        const line = (try stdin.readUntilDelimiterOrEof(&buffer, '\n')) orelse break;
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        if (trimmed.len == 0) continue;

        // Handle commands
        if (std.mem.startsWith(u8, trimmed, "/")) {
            if (std.mem.eql(u8, trimmed, "/quit") or std.mem.eql(u8, trimmed, "/exit")) {
                break;
            } else if (std.mem.eql(u8, trimmed, "/clear")) {
                chat.clearHistory();
                try stdout.print("✓ History cleared\n\n", .{});
                continue;
            } else if (std.mem.eql(u8, trimmed, "/history")) {
                const history = try chat.getHistory();
                defer allocator.free(history);
                try stdout.print("\n{s}\n\n", .{history});
                continue;
            } else if (std.mem.startsWith(u8, trimmed, "/switch ")) {
                const provider_name = std.mem.trim(u8, trimmed[8..], &std.ascii.whitespace);
                const provider = std.meta.stringToEnum(thanos.types.Provider, provider_name) orelse {
                    try stdout.print("❌ Unknown provider: {s}\n", .{provider_name});
                    try stdout.print("Available: anthropic, openai, xai, ollama, github_copilot\n\n", .{});
                    continue;
                };
                chat.switchProvider(provider);
                try stdout.print("✓ Switched to {s}\n\n", .{@tagName(provider)});
                continue;
            } else if (std.mem.eql(u8, trimmed, "/help")) {
                try stdout.print(
                    \\Commands:
                    \\  /switch <provider>  - Switch AI provider
                    \\  /clear              - Clear chat history
                    \\  /history            - Show conversation
                    \\  /quit               - Exit chat
                    \\
                    \\Providers: anthropic, openai, xai, ollama, github_copilot
                    \\
                    \\
                , .{});
                continue;
            } else {
                try stdout.print("❌ Unknown command. Type /help for help\n\n", .{});
                continue;
            }
        }

        // Send message to AI
        const response = chat.sendMessage(trimmed) catch |err| {
            try stdout.print("❌ Error: {s}\n\n", .{@errorName(err)});
            continue;
        };

        try stdout.print("\n{s}\n\n", .{response});
    }

    try stdout.print("\nGoodbye! 👋\n", .{});
}

test "chat session" {
    const allocator = std.testing.allocator;

    // This would require a mock Thanos instance
    // For now, just test basic structure
    _ = allocator;
}
