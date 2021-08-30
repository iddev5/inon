const std = @import("std");

pub const TokenType = enum {
    string,
    identifier,
    number,

    assignment,
    equality,
    plus,
    concat,
    minus,
    multiply,
    repeat,
    divide,
    floor,
    modulo,
    greater,
    less,
    greateql,
    lesseql,

    semicolon,
    lpar,
    rpar,
    lbra,
    rbra,
    lsqr,
    rsqr,
    comma,
    dot,

    eof,
};

pub const Token = struct {
    toktype: TokenType,
    content: []const u8,
};

pub const Lexer = struct {
    src: []const u8,
    pos: u32 = 0,
    line: usize = 1,

    const Self = @This();

    pub fn init(src: []const u8) Self {
        return .{
            .src = src,
        };
    }

    pub fn free(self: *Self) void {
        _ = self;
    }

    inline fn peek(self: *Self) u8 {
        if (self.isEof()) return 0;
        return self.src[self.pos];
    }

    inline fn next(self: *Self) u8 {
        self.pos += 1;
        return self.src[self.pos - 1];
    }

    inline fn skipWhitespace(self: *Self) void {
        while (true) {
            switch (self.peek()) {
                '\n' => {
                    self.line += 1;
                    self.pos += 1;
                },
                ' ', '\r', '\t' => _ = self.next(),
                else => return,
            }
        }
    }

    inline fn isEof(self: *Self) bool {
        return self.pos == self.src.len;
    }

    inline fn matches(self: *Self, c: u8) bool {
        if (self.peek() != c)
            return false;
        self.pos += 1;
        return true;
    }

    pub fn getToken(self: *Self) Token {
        self.skipWhitespace();

        if (self.isEof())
            return self.makeToken(.eof, 0);

        var c = self.next();

        return switch (c) {
            ';' => self.makeToken(.semicolon, 0),
            '=' => self.makeToken(if (self.matches('=')) .equality else .assignment, 0),
            '+' => self.makeToken(if (self.matches('+')) .concat else .plus, 0),
            '-' => self.makeToken(.minus, 0),
            '*' => self.makeToken(if (self.matches('*')) .repeat else .multiply, 0),
            '/' => self.makeToken(if (self.matches('/')) .floor else .divide, 0),
            '%' => self.makeToken(.modulo, 0),
            '(' => self.makeToken(.lpar, 0),
            ')' => self.makeToken(.rpar, 0),
            '{' => self.makeToken(.lbra, 0),
            '}' => self.makeToken(.rbra, 0),
            '[' => self.makeToken(.lsqr, 0),
            ']' => self.makeToken(.rsqr, 0),
            ',' => self.makeToken(.comma, 0),
            '.' => self.makeToken(.dot, 0),
            '>' => self.makeToken(if (self.matches('=')) .greateql else .greater, 0),
            '<' => self.makeToken(if (self.matches('=')) .lesseql else .less, 0),
            '\"' => self.string(),
            else => {
                if (std.ascii.isDigit(c)) return self.number();
                if (std.ascii.isAlpha(c) or c == '_') return self.identifier();
                return self.makeToken(.eof, 0);
            },
        };
    }

    inline fn makeToken(self: *Self, toktype: TokenType, start: usize) Token {
        return Token{ .toktype = toktype, .content = self.src[start..self.pos] };
    }

    fn string(self: *Self) Token {
        _ = self.next();
        const start = self.pos - 1;
        while (self.peek() != '\"')
            _ = self.next();

        const tok = self.makeToken(.string, start);
        _ = self.next();

        return tok;
    }

    fn number(self: *Self) Token {
        const start = self.pos - 1;
        while (std.ascii.isDigit(self.peek()))
            _ = self.next();

        return self.makeToken(.number, start);
    }

    fn identifier(self: *Self) Token {
        const start = self.pos - 1;
        while (std.ascii.isAlNum(self.peek()) or self.peek() == '_')
            _ = self.next();

        return self.makeToken(.identifier, start);
    }
};
