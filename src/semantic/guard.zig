pub var resolution_failed = false;
pub var cycle_detected = false;
const Key = struct { file: File.Index, node: std.zig.Ast.Node.Index, operation: u8, name: []const u8 };
var stack: [512]Key = undefined;
var stack_len: usize = 0;
pub fn enter(file: File.Index, node: std.zig.Ast.Node.Index, operation: u8) bool {
    return enterNamed(file, node, operation, "");
}
pub fn enterChild(file: File.Index, node: std.zig.Ast.Node.Index, name: []const u8) bool {
    return enterNamed(file, node, 2, name);
}
fn enterNamed(file: File.Index, node: std.zig.Ast.Node.Index, operation: u8, name: []const u8) bool {
    for (stack[0..stack_len]) |key| if (key.file == file and key.node == node and key.operation == operation and std.mem.eql(u8, key.name, name)) {
        resolution_failed = true;
        cycle_detected = true;
        return false;
    };
    if (stack_len == stack.len) {
        resolution_failed = true;
        return false;
    }
    stack[stack_len] = .{ .file = file, .node = node, .operation = operation, .name = name };
    stack_len += 1;
    return true;
}
pub fn leave() void {
    stack_len -= 1;
}
