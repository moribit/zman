// UI and lexer roles share one basic ANSI palette.
pub const Role = enum {
    title,
    kind,
    section,
    metadata_key,
    symbol,
    secondary,
    keyword,
    builtin,
    literal,
    number,
    comment,
    identifier,
    punctuation,
};
pub const reset = "\x1b[0m";
pub fn ansi(role: Role) []const u8 {
    return switch (role) {
        .title, .section => "\x1b[1;36m",
        .kind => "\x1b[1m",
        .metadata_key, .secondary => "\x1b[2m",
        .symbol, .builtin => "\x1b[36m",
        .keyword => "\x1b[35m",
        .literal => "\x1b[32m",
        .number => "\x1b[33m",
        .comment => "\x1b[90m",
        .identifier => "\x1b[39m",
        .punctuation => "\x1b[34m",
    };
}
