const std = @import("std");
const Method = std.http.Method;
const URL = @import("url");
const logger = @import("logger.zig").init(.{});

const Context = @import("context.zig");
const Request = @import("request.zig");
const Response = @import("response.zig");
const Handler = @import("handler.zig");
const Middleware = @import("middleware.zig");
const HandlerFn = Handler.HandlerFn;
const HandlerChain = Handler.Chain;

pub const Route = @This();
const Self = @This();

allocator: std.mem.Allocator = std.heap.page_allocator,

method: Method = undefined,

path: []const u8 = "*",

handlers_chain: std.ArrayList(HandlerFn) = std.ArrayList(HandlerFn).init(std.heap.page_allocator),

pub fn init(self: Self) Route {
    return .{
        .allocator = self.allocator,
        .method = self.method,
        .path = self.path,
        .handlers_chain = self.handlers_chain,
    };
}

pub const RouteError = error{
    None,

    // 404 Not Found
    NotFound,
    // 405 Method Not Allowed
    MethodNotAllowed,
};

pub fn match(self: *Route, method: Method, target: []const u8) anyerror!*Route {
    var url = URL.init(.{});
    const url_target = try url.parseUrl(target);
    const path = url_target.path;

    if (self.isPathMatch(path)) {
        if (self.isMethodAllowed(method)) {
            return self;
        }
        // found route but method not allowed
        return RouteError.MethodNotAllowed;
    }

    return RouteError.NotFound;
}

pub fn create(path: []const u8, http_method: Method, handler: HandlerFn) Route {
    var r = Route.init(.{ .method = http_method, .path = path });
    r.handlers_chain.append(handler) catch |err| {
        std.debug.print("failed to append handler to route: {any}", .{err});
    };
    return r;
}

pub fn any(path: []const u8, handler: anytype) Route {
    const ms = [_]Method{ .GET, .POST, .PUT, .DELETE, .PATCH, .OPTIONS, .HEAD, .CONNECT, .TRACE };
    for (ms) |m| {
        try create(path, m, handler);
    }
}

pub fn isHandlerExists(self: *Route, handler: HandlerFn) bool {
    for (self.handlers_chain.items) |h| {
        if (h == handler) {
            return true;
        }
    }
    return false;
}

pub fn get(path: []const u8, handler: anytype) Route {
    return create(path, .GET, handler);
}

pub fn post(path: []const u8, handler: anytype) Route {
    return create(path, .POST, handler);
}
pub fn put(path: []const u8, handler: anytype) Route {
    return create(path, .PUT, handler);
}
pub fn delete(path: []const u8, handler: anytype) Route {
    return create(path, .DELETE, handler);
}
pub fn patch(path: []const u8, handler: anytype) Route {
    return create(path, .PATCH, handler);
}
pub fn options(path: []const u8, handler: anytype) Route {
    return create(path, .OPTIONS, handler);
}
pub fn head(path: []const u8, handler: anytype) Route {
    return create(path, .HEAD, handler);
}
pub fn connect(path: []const u8, handler: anytype) Route {
    return create(path, .CONNECT, handler);
}
pub fn trace(path: []const u8, handler: anytype) Route {
    return create(path, .TRACE, handler);
}

pub fn getPath(self: *Route) []const u8 {
    return self.path;
}

pub fn getHandler(self: *Route) Handler.HandlerFn {
    return &self.handler;
}

pub fn handle(self: *Route, ctx: *Context) anyerror!void {
    // return try self.handler(ctx);
    for (self.handlers_chain.items) |handler| {
        handler(ctx) catch |err| {
            std.log.err("handler error: {any}", .{err});
            return err;
        };
    }
}

pub fn isMethodAllowed(self: *Route, method: Method) bool {
    if (self.method == method) {
        return true;
    }

    return false;
}

pub fn isPathMatch(self: *Route, path: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(self.path, "*")) {
        return true;
    }
    return std.ascii.eqlIgnoreCase(self.path, path);
}

pub fn isStaticRoute(self: *Route, target: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(self.path, "*")) {
        return true;
    }

    // not server root
    if (std.mem.eql(u8, target, "/") or std.mem.eql(u8, self.path, "") or std.mem.eql(u8, self.path, "/")) {
        return false;
    }

    var targets = std.mem.splitSequence(u8, target, "/");
    var ps = std.mem.splitSequence(u8, self.path, "/");

    _ = targets.first();
    _ = ps.first();

    while (true) {
        const t = targets.next().?;
        const pp = ps.next().?;
        if (std.ascii.eqlIgnoreCase(t, "") or std.ascii.eqlIgnoreCase(pp, "")) {
            break;
        }

        if (std.ascii.eqlIgnoreCase(t, pp)) {
            return true;
        }
        return false;
    }

    return std.ascii.eqlIgnoreCase(self.path, target);
}

pub fn isMatch(self: *Route, method: Method, path: []const u8) bool {
    if (self.isPathMatch(path) and self.isMethodAllowed(method)) {
        return true;
    }

    return false;
}

pub fn use(self: *Route, handler: anytype) anyerror!void {
    self.handlers_chain.append(handler) catch |err| {
        return err;
    };
}
