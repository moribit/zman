const std = @import("std");
const Entry = @import("index.zig").Entry;
pub const Result = struct { entry_index: usize, score: u32, match_kind: enum { symbol, docs, fuzzy } };
pub fn normalize(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (text, 0..) |c, i| {
        if (!std.ascii.isAlphanumeric(c)) {
            if (out.items.len > 0 and out.items[out.items.len - 1] != ' ') try out.append(a, ' ');
            continue;
        }
        if (i > 0 and std.ascii.isUpper(c) and (std.ascii.isLower(text[i - 1]) or (i + 1 < text.len and std.ascii.isUpper(text[i - 1]) and std.ascii.isLower(text[i + 1])))) try out.append(a, ' ');
        try out.append(a, std.ascii.toLower(c));
    }
    while (out.items.len > 0 and out.items[out.items.len - 1] == ' ') out.items.len -= 1;
    return out.toOwnedSlice(a);
}
fn allTokens(query: []const u8, text: []const u8) bool {
    var it = std.mem.tokenizeScalar(u8, query, ' ');
    while (it.next()) |token| {
        var words = std.mem.tokenizeScalar(u8, text, ' ');
        var found = false;
        while (words.next()) |word| {
            if (std.mem.eql(u8, token, word)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return query.len != 0;
}
pub fn exact(entries: []const Entry, query: []const u8) ?usize {
    for (entries, 0..) |e, i| {
        if (std.mem.eql(u8, query, e.fq_name)) return i;
        if (std.mem.startsWith(u8, e.fq_name, "std.") and std.mem.eql(u8, query, e.fq_name[4..])) return i;
    }
    var one: ?usize = null;
    for (entries, 0..) |e, i| if (std.mem.eql(u8, e.short_name, query)) {
        if (one != null) return null;
        one = i;
    };
    return one;
}
pub fn distance(a: []const u8, b: []const u8) usize {
    if (a.len > 256 or b.len > 256) return 999;
    var previous: [257]usize = undefined;
    var current: [257]usize = undefined;
    for (0..b.len + 1) |i| previous[i] = i;
    for (a, 0..) |ca, i| {
        current[0] = i + 1;
        for (b, 0..) |cb, j| current[j + 1] = @min(@min(current[j] + 1, previous[j + 1] + 1), previous[j] + @intFromBool(std.ascii.toLower(ca) != std.ascii.toLower(cb)));
        previous = current;
    }
    return previous[b.len];
}
pub fn search(a: std.mem.Allocator, entries: []const Entry, query: []const u8, limit: usize) ![]Result {
    const q = try normalize(a, query);
    defer a.free(q);
    var results: std.ArrayList(Result) = .empty;
    errdefer results.deinit(a);
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    const dotted = std.mem.indexOfScalar(u8, query, '.') != null and std.mem.indexOfScalar(u8, query, ' ') == null;
    for (entries, 0..) |e, i| {
        _ = scratch.reset(.retain_capacity);
        const symbol = try normalize(temporary, e.fq_name);
        const short = try normalize(temporary, e.short_name);
        const docs = try normalize(temporary, e.docs);
        var score: u32 = 0;
        var kind: @FieldType(Result, "match_kind") = .symbol;
        if (std.ascii.eqlIgnoreCase(query, e.fq_name)) score = 10000 else if (std.ascii.eqlIgnoreCase(query, e.short_name)) score = 9000 else if (allTokens(q, short)) score = 8000 else if (allTokens(q, symbol)) score = 7000 else if (std.mem.startsWith(u8, short, q) and q.len != 0) score = 6500 else if (q.len != 0 and std.mem.indexOf(u8, docs, q) != null) {
            score = 3000;
            kind = .docs;
        } else if (allTokens(q, docs)) {
            score = 2500;
            kind = .docs;
        } else {
            var tokens = std.mem.tokenizeScalar(u8, q, ' ');
            while (tokens.next()) |token| if (std.mem.indexOf(u8, docs, token) != null) {
                score += 100;
                kind = .docs;
            };
            if (score == 0) {
                const signature = try normalize(temporary, e.signature);
                const path = try normalize(temporary, e.source_path);
                if (allTokens(q, signature)) score = 80 else if (allTokens(q, path)) score = 40;
            }
        }
        if ((score == 0 or (dotted and score < 6500)) and std.mem.indexOfScalar(u8, query, ' ') == null) {
            const name = if (std.mem.startsWith(u8, query, "std.")) e.fq_name else if (std.mem.indexOfScalar(u8, query, '.') != null) e.fq_name[4..] else e.short_name;
            const d = distance(query, name);
            if (d <= (if (query.len > 8) @as(usize, 2) else 1)) {
                score = @intCast((if (dotted) @as(usize, 5000) else 20) - d);
                kind = .fuzzy;
            }
        }
        if (score > 0) try results.append(a, .{ .entry_index = i, .score = score, .match_kind = kind });
    }
    std.mem.sort(Result, results.items, entries, struct {
        fn less(es: []const Entry, x: Result, y: Result) bool {
            if (x.score != y.score) return x.score > y.score;
            const xn = es[x.entry_index].fq_name;
            const yn = es[y.entry_index].fq_name;
            if (xn.len != yn.len) return xn.len < yn.len;
            return std.mem.lessThan(u8, xn, yn);
        }
    }.less);
    var groups: std.AutoHashMapUnmanaged(usize, void) = .empty;
    defer groups.deinit(a);
    var count: usize = 0;
    for (results.items) |result| {
        const entry = entries[result.entry_index];
        const canonical = entry.target_entry orelse result.entry_index;
        const gop = try groups.getOrPut(a, canonical);
        if (gop.found_existing) continue;
        results.items[count] = result;
        count += 1;
    }
    results.items.len = count;
    if (dotted and results.items.len > 0 and results.items[0].match_kind == .fuzzy) {
        var fuzzy_count: usize = 0;
        while (fuzzy_count < results.items.len and results.items[fuzzy_count].match_kind == .fuzzy) : (fuzzy_count += 1) {}
        results.items.len = fuzzy_count;
    }
    results.items.len = @min(limit, results.items.len);
    return results.toOwnedSlice(a);
}
test "camel and acronym tokens" {
    const a = std.testing.allocator;
    const s = try normalize(a, "openFile HTTPServer_file");
    defer a.free(s);
    try std.testing.expectEqualStrings("open file http server file", s);
    try std.testing.expectEqual(@as(usize, 1), distance("posx.read", "posix.read"));
}
