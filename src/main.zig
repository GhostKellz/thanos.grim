const std = @import("std");
const thanos_grim = @import("thanos_grim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🌌 Thanos Grim Plugin - Test CLI\n", .{});
    std.debug.print("=====================================\n\n", .{});

    // Test plugin initialization
    var plugin = try thanos_grim.ThanosGrimPlugin.init(allocator);
    defer plugin.deinit();

    std.debug.print("✅ Plugin initialized successfully\n", .{});

    // Test Thanos initialization
    try plugin.initializeThanos();
    std.debug.print("✅ Thanos initialized successfully\n", .{});

    // Test listing providers
    const providers = try plugin.listProviders();
    defer allocator.free(providers);

    std.debug.print("\n📡 Available Providers:\n", .{});
    for (providers) |prov| {
        std.debug.print("  - {s}: {s}\n", .{
            prov.provider.toString(),
            if (prov.available) "available" else "unavailable"
        });
    }

    // Test stats
    const stats = try plugin.getStats();
    std.debug.print("\n📊 Statistics:\n", .{});
    std.debug.print("  Providers available: {d}\n", .{stats.providers_available});

    std.debug.print("\n✨ All tests passed!\n", .{});
}
