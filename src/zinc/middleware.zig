const std = @import("std");
const http = std.http;
const Method = http.Method;

const zinc = @import("../zinc.zig");

const Handler = zinc.Handler;
const HandlerFn = Handler.HandlerFn;
const HandlerChain = Handler.Chain;
const Context = zinc.Context;

pub const Middleware = @This();
const Self = @This();

methods: []const Method = &[_]Method{
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

handlers: std.ArrayList(HandlerFn) = std.ArrayList(HandlerFn).init(std.heap.page_allocator),

pub fn init(self: Self) Middleware {
    return .{
        .methods = self.methods,
        .handlers = self.handlers,
    };
}

pub fn add(self: *Self, handler: HandlerFn) anyerror!void {
    try self.handlers.append(handler);
}

pub fn getHandler(self: *Self, method: Method) !HandlerFn {
    const index = self.methods.index(method);
    if (index == self.methods.len) {
        return null;
    }
    return self.handlers[index];
}

pub fn handle(self: *Self, ctx: *Context) anyerror!void {
    const method = ctx.request.method();
    const handler = try self.getHandler(method);
    if (handler == null) {
        return;
    }
    return handler(ctx);
}

pub fn cors() HandlerFn {
    const H = struct {
        fn handle(ctx: *Context) anyerror!void {
            try ctx.request.setHeader("Access-Control-Allow-Origin", ctx.request.getHeader("Origin") orelse "*");

            if (ctx.request.method == .OPTIONS) {
                try ctx.request.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
                try ctx.request.setHeader("Access-Control-Allow-Headers", "Content-Type");
                try ctx.request.setHeader("Access-Control-Allow-Private-Network", "true");

                try ctx.response.sendStatus(.no_content);
                return;
            }

            return ctx.next();
        }
    };
    return H.handle;
}

// pub const cors = struct {
//     // "Access-Control-Allow-Origin"
//     const Origin: []const u8 = "*";
//     // "Access-Control-Allow-Methods"
//     const Methods: []std.http.Method = &[_]std.http.Method{ .GET, .POST, .PUT, .DELETE, .OPTIONS };
//     // "Access-Control-Allow-Headers"
//     const Headers: []const u8 = "Content-Type";
//     // "Access-Control-Allow-Private-Network"
//     const Private: bool = true;
//     // "Access-Control-Max-Age"
//     const MaxAge: usize = 3600;
//     pub fn init(self: cors) cors {
//         return .{
//             .Origin = self.Origin,
//             .Methods = self.Methods,
//             .Headers = self.Headers,
//             .Private = self.Private,
//             .MaxAge = self.MaxAge,
//         };
//     }
// };
