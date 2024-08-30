const std = @import("std");
const Allocator = std.mem.Allocator;
const heap = std.heap;
const page_allocator = heap.page_allocator;
const print = std.debug.print;
const URL = @import("url");
const Context = @import("context.zig");
const Request = @import("request.zig");
const Response = @import("response.zig");
const Route = @import("route.zig");
const Handler = @import("handler.zig");
const HandlerFn = Handler.HandlerFn;
const Middleware = @import("middleware.zig");

const RouterGroup = @import("routergroup.zig");

pub const Router = @This();
const Self = @This();

methods: []const std.http.Method = &[_]std.http.Method{
    .GET,
    .POST,
    .PUT,
    .DELETE,
    .OPTIONS,
    .HEAD,
    .PATCH,
    .CONNECT,
    .TRACE,
},

allocator: Allocator = page_allocator,
routes: std.ArrayList(Route) = std.ArrayList(Route).init(page_allocator),
// catchers: std.AutoHashMap(std.http.Status, HandlerFn) = std.AutoHashMap(std.http.Status, HandlerFn).init(std.heap.page_allocator),

pub fn init(self: Self) Router {
    return .{
        .allocator = self.allocator,
        .routes = self.routes,
    };
}

pub fn deinit(self: *Self) void {
    self.routes.deinit();
}

pub fn handleContext(self: *Self, ctx: Context) anyerror!void {
    const routes = self.routes.items;

    for (routes) |*route| {
        if (route.match(ctx.request.method, ctx.request.path)) {
            return try route.HandlerFn(ctx, ctx.request, ctx.response);
        }
    }
}

/// Rebuild all routes.
pub fn rebuild(self: *Self) !void {
    var all_route_handlers = std.ArrayList(HandlerFn).init(self.allocator);

    for (self.routes.items) |*route| {
        if (std.mem.eql(u8, route.path, "*")) {
            try all_route_handlers.appendSlice(route.handlers_chain.items);
            continue;
        }
    }

    for (self.routes.items) |*route| {
        if (std.mem.eql(u8, route.path, "*")) {
            continue;
        }

        try route.handlers_chain.appendSlice(all_route_handlers.items);
    }
}

/// Return routes.
pub fn getRoutes(self: *Self) std.ArrayList(Route) {
    return self.routes;
}

pub fn add(self: *Self, method: std.http.Method, path: []const u8, handler: anytype) anyerror!void {
    if (self.routes.items.len == 0) {
        try self.addRoute(Route.create(path, method, handler));
        return;
    }

    for (self.routes.items) |*route| {
        if (std.mem.eql(u8, route.path, path) and route.method == method) {
            if (!route.isHandlerExists(handler)) {
                try route.handlers_chain.append(handler);
                return;
            }
            return;
        }
    }

    try self.addRoute(Route.create(path, method, handler));
    return;
}

pub fn addAny(self: *Self, http_methods: []const std.http.Method, path: []const u8, handler: HandlerFn) anyerror!void {
    for (http_methods) |method| {
        if (self.routes.items.len == 0) {
            try self.add(method, path, handler);
            continue;
        }

        for (self.routes.items) |*route| {
            if (std.mem.eql(u8, route.path, path) and route.method == method) {
                if (!route.isHandlerExists(handler)) {
                    try route.handlers_chain.append(handler);
                }
                continue;
            }
        }

        try self.add(method, path, handler);
    }
}

pub fn any(self: *Self, path: []const u8, handler: anytype) anyerror!void {
    for (self.methods) |method| {
        try self.add(method, path, handler);
    }
}

pub fn addRoute(self: *Self, route: Route) anyerror!void {
    try self.routes.append(route);
}

pub fn get(self: *Self, path: []const u8, handler: anytype) anyerror!void {
    try self.add(.GET, path, handler);
}
pub fn post(self: *Self, path: []const u8, handler: anytype) anyerror!void {
    try self.add(.POST, path, handler);
}
pub fn put(self: *Self, path: []const u8, handler: anytype) anyerror!void {
    try self.add(.PUT, path, handler);
}
pub fn delete(self: *Self, path: []const u8, handler: anytype) anyerror!void {
    try self.add(.DELETE, path, handler);
}
pub fn patch(self: *Self, path: []const u8, handler: anytype) anyerror!void {
    try self.add(.PATCH, path, handler);
}
pub fn options(self: *Self, path: []const u8, handler: anytype) anyerror!void {
    try self.add(.OPTIONS, path, handler);
}
pub fn head(self: *Self, path: []const u8, handler: anytype) anyerror!void {
    try self.add(.HEAD, path, handler);
}
pub fn connect(self: *Self, path: []const u8, handler: anytype) anyerror!void {
    try self.add(.CONNECT, path, handler);
}
pub fn trace(self: *Self, path: []const u8, handler: anytype) anyerror!void {
    try self.add(.TRACE, path, handler);
}
pub fn matchRoute(self: *Self, method: std.http.Method, target: []const u8) anyerror!*Route {
    var err = Route.RouteError.NotFound;
    var url = URL.init(.{});
    const url_target = try url.parseUrl(target);
    const path = url_target.path;
    for (self.routes.items) |*route| {
        if (std.mem.eql(u8, path, "*")) {
            if (route.isMethodAllowed(method)) {
                return route;
            }
            err = Route.RouteError.MethodNotAllowed;
        }

        if (route.isPathMatch(path)) {
            if (route.isMethodAllowed(method)) {
                return route;
            }
            err = Route.RouteError.MethodNotAllowed;
        }

        // match static file
        if (route.isStaticRoute(path)) {
            if (route.isMethodAllowed(method)) {
                return route;
            }
            err = Route.RouteError.MethodNotAllowed;
        }
    }

    return err;
}

pub fn use(self: *Self, path: []const u8, handler: anytype) anyerror!void {
    const routes = self.routes.items;

    for (routes) |*route| {
        if (route.isPathMatch(path) or std.mem.eql(u8, path, "*")) {
            try route.use(handler);
        }
    }
}

pub fn group(self: *Self, prefix: []const u8, handler: anytype) anyerror!RouterGroup {
    self.any(prefix, handler) catch |err| return err;

    const g = RouterGroup{
        .router = self,
        .prefix = prefix,
        .root = true,
    };

    return g;
}

pub inline fn static(self: *Self, relativePath: []const u8, filepath: []const u8) anyerror!void {
    try checkPath(filepath);

    if (std.mem.eql(u8, relativePath, "")) {
        return error.Empty;
    }

    if (std.mem.eql(u8, filepath, "") or std.mem.eql(u8, filepath, "/")) {
        return error.AccessDenied;
    }

    if (std.fs.path.basename(filepath).len == 0) {
        return self.staticDir(relativePath, filepath);
    }

    return self.staticFile(relativePath, filepath);
}

pub inline fn staticFile(self: *Self, target: []const u8, filepath: []const u8) anyerror!void {
    try checkPath(filepath);
    const H = struct {
        fn handle(ctx: *Context) anyerror!void {
            try ctx.file(filepath, .{});
        }
    };
    try self.get(target, H.handle);
    try self.head(target, H.handle);
}

pub inline fn staticDir(self: *Self, target: []const u8, filepath: []const u8) anyerror!void {
    try checkPath(filepath);
    const H = struct {
        fn handle(ctx: *Context) anyerror!void {
            try ctx.dir(filepath, .{});
        }
    };
    try self.get(target, H.handle);
    try self.head(target, H.handle);
}

fn staticFileHandler(self: *Self, relativePath: []const u8, handler: HandlerFn) anyerror!void {
    try checkPath(relativePath);

    try self.get(relativePath, handler);
    try self.head(relativePath, handler);
}

fn checkPath(path: []const u8) anyerror!void {
    for (path) |c| {
        if (c == '*' or c == ':') {
            return error.Unreachable;
        }
    }
}
