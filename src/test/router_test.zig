const std = @import("std");
const testing = std.testing;
const http = std.http;

const zinc = @import("../zinc.zig");
const HandlerFn = zinc.HandlerFn;
const Request = zinc.Request;
const Response = zinc.Response;
const Context = zinc.Context;

const Route = zinc.Route;
const Router = zinc.Router;
const RouteError = Route.RouteError;

fn createContext(method: std.http.Method, target: []const u8) anyerror!*Context {
    const allocator = std.testing.allocator;

    var req = zinc.Request.init(.{ .req = undefined, .method = method, .target = target, .allocator = allocator });
    const res = try zinc.Response.init(.{ .allocator = allocator });
    const ctx = try zinc.Context.init(.{ .request = &req, .response = res, .allocator = allocator });
    return ctx;
}

test "Router. Handle Request" {
    var router = try Router.init(.{ .allocator = std.testing.allocator });
    defer router.deinit();

    const handle = struct {
        fn anyHandle(ctx: *Context) anyerror!void {
            try ctx.text("Hello Zinc!", .{});
        }
    }.anyHandle;
    try router.get("/", handle);

    const route = try router.getRoute(.GET, "/");
    try testing.expectEqualStrings("/", route.path);

    const routes = router.getRoutes();
    defer routes.deinit();

    try std.testing.expectEqual(1, routes.items.len);

    try router.post("/", handle);

    // GET Request.
    // var ctx_get = try createContext(.GET, "/");
    // try ctx_get.handlers.appendSlice(route.handlers.items);
    // try ctx_get.handlersProcess();
    // try testing.expectEqual(.ok, ctx_get.response.status);
    // try testing.expectEqualStrings("Hello Zinc!", ctx_get.response.body.?);
    // defer ctx_get.destroy();
    // std.debug.print("\r\n Done handle GET request test", .{});

    // POST Request.
    // var ctx_post = try createContext(.POST, "/");
    // try router.prepareContext(ctx_post);
    // TODO
    // try testing.expectEqual(.ok, ctx_post.response.status);
    // try testing.expectEqualStrings("Hello Zinc!", ctx_post.response.body.?);
    // defer ctx_post.destroy();
    // std.debug.print("\r\n Done handle POST request test", .{});

    // Not found
    var ctx_not_found = try createContext(.GET, "/not-found");
    router.prepareContext(ctx_not_found) catch |err| {
        try testing.expect(err == RouteError.NotFound);
    };
    defer ctx_not_found.destroy();

    // Method not allowed
    var ctx_not_allowed = try createContext(.PUT, "/");
    router.prepareContext(ctx_not_allowed) catch |err| {
        try testing.expect(err == RouteError.MethodNotAllowed);
    };
    defer ctx_not_allowed.destroy();
}

test "router, routeTree and router.getRoute" {
    const allocator = std.testing.allocator;

    var router = try Router.init(.{ .allocator = allocator });
    defer router.deinit();

    const handler = struct {
        fn anyHandle(ctx: *Context) anyerror!void {
            try ctx.text("Hello Zinc!", .{});
        }
    }.anyHandle;

    var static_route = try Route.init(.{
        .method = .GET,
        .path = "/static",
        .allocator = allocator,
        .handlers = std.ArrayList(HandlerFn).init(allocator),
    });
    // defer static_route.deinit();

    try static_route.handlers.append(handler);
    try router.addRoute(static_route);

    const TestCase = struct {
        reqMethod: std.http.Method,
        reqPath: []const u8,
        expected: anyerror!*Route,
    };
    const testCases = [_]TestCase{
        .{ .reqMethod = .GET, .reqPath = "/static", .expected = static_route },
        .{ .reqMethod = .GET, .reqPath = "/static?code=123", .expected = static_route },
        .{ .reqMethod = .GET, .reqPath = "/static?code=123&state=xyz#foo", .expected = static_route },

        .{ .reqMethod = .POST, .reqPath = "/static", .expected = RouteError.MethodNotAllowed },
        .{ .reqMethod = .GET, .reqPath = "/static/foo", .expected = RouteError.NotFound },
        .{ .reqMethod = .GET, .reqPath = "/static/foo/bar", .expected = RouteError.NotFound },
        .{ .reqMethod = .GET, .reqPath = "/foo/static", .expected = RouteError.NotFound },
        .{ .reqMethod = .GET, .reqPath = "/foo/static/bar", .expected = RouteError.NotFound },
        .{ .reqMethod = .GET, .reqPath = "/foo/static/hello.css", .expected = RouteError.NotFound },
    };

    for (testCases, 0..) |tc, i| {
        const rTree_route = router.getRoute(tc.reqMethod, tc.reqPath) catch |err| {
            _ = i;
            try testing.expect(err == (tc.expected catch |e| e));
            continue;
        };

        try testing.expectEqual(rTree_route, (try tc.expected));
    }
}
