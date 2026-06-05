const std = @import("std");

fn Boxed(comptime T: type) type {
    return struct {
        root: *const T,
    };
}

pub fn makeBox(comptime T: type, value: *const T) Boxed(T) {
    return .{ .root = value };
}

const Plain = struct {
    value: usize,
    other: usize,
};

test "generic return type debug location" {
    var plain = Plain{ .value = 1, .other = 2 };
    const boxed = makeBox(Plain, &plain);
    try std.testing.expect(boxed.root.other == 2);
}
