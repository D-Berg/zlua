//! Here we list all functions and types from the C API in alphabetical order. Each function has an indicator like this: [-o, +p, x]
//! The first field, o, is how many elements the function pops from the stack.
//! The second field, p, is how many elements the function pushes onto the stack.
//! (Any function always pushes its results after popping its arguments.)
//! A field in the form x|y means the function can push (or pop) x or y elements,
//! depending on the situation; an interrogation mark '?' means that we cannot know
//! how many elements the function pops/pushes by looking only at its arguments.
//! (For instance, they may depend on what is in the stack.)
//! The third field, x, tells whether the function may raise errors: '-' means the function never raises any error;
//! 'm' means the function may raise only out-of-memory errors;
//! 'v' means the function may raise the errors explained in the text;
//! 'e' means the function can run arbitrary Lua code, either directly or through metamethods, and therefore may raise any errors.

const std = @import("std");
const c = @import("c");
const Allocator = std.mem.Allocator;

pub const LuaState = c.lua_State;

pub const MultiRet = c.LUA_MULTRET;

pub const Error = error{
    NewStateError,
    UnknownError,
};

pub const Lib = struct {
    pub const base = c.luaopen_base;
    pub const coroutine = c.luaopen_coroutine;
    pub const package = c.luaopen_package;
    pub const utf8 = c.luaopen_utf8;
    // TODO: add more libs;
};

pub const State = struct {
    inner: *LuaState = undefined,
    /// The allocator for which lua will use for all allocations.
    /// Set to null to use malloc.
    gpa: ?Allocator = null,

    /// Initialize a Lua State.
    /// This is an intrusive initiatialisation since it
    /// requires a stable pointer to the gpa if one is set.
    ///
    /// # Example:
    ///
    /// ```zig
    /// var lua: zlua.State = .{ .gpa = gpa };
    /// try lua.new();
    /// ```
    pub fn new(self: *State) Error!void {
        if (self.gpa) |*gpa| {
            if (c.lua_newstate(alloc, gpa)) |state| {
                self.inner = state;
                return;
            }
            return Error.NewStateError;
        } else if (c.luaL_newstate()) |state| {
            self.inner = state;
            return;
        } else return Error.NewStateError;
    }

    /// Close all active to-be-closed variables in the main thread,
    /// release all objects in the given Lua state
    /// (calling the corresponding garbage-collection metamethods, if any),
    /// and frees all dynamic memory used by this state.
    ///
    /// On several platforms, you may not need to call this function,
    /// because all resources are naturally released when the host program ends.
    /// On the other hand, long-running programs that create multiple states,
    /// such as daemons or web servers, will probably need to close states as soon as they are not needed.
    pub fn close(self: *const State) void {
        c.lua_close(self.inner);
    }
    /// Performs an arithmetic or bitwise operation over the two values (or one, in the case of negations)
    /// at the top of the stack, with the value on the top being the second operand,
    /// pops these values, and pushes the result of the operation.
    /// The function follows the semantics of the corresponding Lua operator (that is, it may call metamethods).
    pub fn arith(self: *const State, op: Op) void {
        c.lua_arith(self.inner, op);
    }

    /// Opens all standard Lua libraries into the given state.
    pub fn openLibs(self: *const State) void {
        c.luaL_openlibs(self.inner);
    }

    /// Creates a new empty table and pushes it onto the stack. It is equivalent to `createTable(0, 0)`
    pub fn newTable(self: *const State) void {
        self.createTable(0, 0);
    }

    pub fn createTable(self: *const State, narr: usize, nrec: usize) void {
        c.lua_createtable(self.inner, @intCast(narr), @intCast(nrec));
    }

    /// Does the equivalent to `t[k] = v`,
    /// where t is the value at the given index and v is the value on the top of the stack.
    /// This function pops the value from the stack. As in Lua,
    /// this function may trigger a metamethod for the "newindex" event (see §2.4).
    pub fn setField(self: *const State, index: isize, k: [:0]const u8) void {
        c.lua_setfield(self.inner, @intCast(index), k);
    }
    /// If package.loaded[modname] is not true,
    /// calls the function openf with the string modname as an argument
    /// and sets the call result to package.loaded[modname], as if that function has been called through require.
    ///
    /// If glb is true, also stores the module into the global modname.
    ///
    /// Leaves a copy of the module on the stack.
    pub fn requiref(self: *const State, modname: [:0]const u8, open_l: CFunction, glb: bool) void {
        c.luaL_requiref(self.inner, modname, open_l, @intFromBool(glb));
    }

    /// Pushes the string pointed to by s with size len onto the stack.
    /// Lua will make or reuse an internal copy of the given string,
    /// so the memory at `str` can be freed or reused immediately after the function returns.
    /// The string can contain any binary data, including embedded zeros.
    pub fn pushlString(self: *const State, str: []const u8) []const u8 {
        const ptr = c.lua_pushlstring(self.inner, str.ptr, str.len);
        var lua_str: []const u8 = undefined;
        lua_str.ptr = ptr;
        lua_str.len = str.len;
        return lua_str;
    }

    pub fn pushLightUserdata(self: *const State, p: ?*anyopaque) void {
        c.lua_pushlightuserdata(self.inner, p);
    }

    pub fn pushCFunction(self: *const State, f: CFunction) void {
        pushCClosure(self, f, 0);
    }
    pub fn pushCClosure(self: *const State, f: CFunction, n: usize) void {
        c.lua_pushcclosure(self.inner, f, @intCast(n));
    }
    /// Loads a string as a Lua chunk. This function uses lua_load to load the chunk in the zero-terminated string s.
    /// This function returns the same results as lua_load.
    /// Also as lua_load, this function only loads the chunk; it does not run it.
    pub fn loadString(state: *const State, string: [:0]const u8) Error!void {
        const rc = c.luaL_loadstring(state.inner, string);
        try checkError(state, rc);
    }

    pub fn loadBufferx(self: *const State, buff: []const u8, name: [:0]const u8, mode: [*c]const u8) Error!void {
        try checkError(self, c.luaL_loadbufferx(self.inner, buff.ptr, buff.len, name, mode));
    }

    pub fn loadBuffer(self: *const State, buff: []const u8, name: [:0]const u8) Error!void {
        try self.loadBufferx(buff, name, null);
    }
    fn printLuaError(state: ?*c.lua_State) void {
        var len: usize = 0;
        const msg = c.lua_tolstring(state, -1, &len);
        if (msg != null) std.debug.print("{s}\n", .{msg[0..len]});
    }

    /// Calls a function (or a callable object) in protected mode.
    /// Both nargs and nresults have the same meaning as in lua_call.
    /// If there are no errors during the call, lua_pcall behaves exactly like lua_call.
    /// However, if there is any error, lua_pcall catches it, pushes a single value on the stack (the error object),
    /// and returns an error code. Like lua_call, lua_pcall always removes the function and its arguments from the stack.
    ///
    /// If msgh is 0, then the error object returned on the stack is exactly the original error object.
    /// Otherwise, msgh is the stack index of a message handler.
    /// (This index cannot be a pseudo-index.) In case of runtime errors,
    /// this handler will be called with the error object and its return value will be the object returned on the stack by lua_pcall.
    ///
    /// Typically, the message handler is used to add more debug information to the error object,
    /// such as a stack traceback. Such information cannot be gathered after the return of lua_pcall,
    /// since by then the stack has unwound.
    ///
    /// The lua_pcall function returns one of the following status codes: LUA_OK, LUA_ERRRUN, LUA_ERRMEM, or LUA_ERRERR.
    pub fn pcall(state: *State, nargs: isize, nresults: isize, msgh: isize) !void {
        try state.pcallk(nargs, nresults, msgh, 0, null);
    }

    /// This function behaves exactly like lua_pcall, except that it allows the called function to yield (see §4.5).
    pub fn pcallk(state: *const State, nargs: isize, nresults: isize, msgh: isize, ctx: isize, k: KFunction) !void {
        const rc = c.lua_pcallk(
            state.inner,
            @as(c_int, @intCast(nargs)),
            @as(c_int, @intCast(nresults)),
            @as(c_int, @intCast(msgh)),
            ctx,
            @ptrCast(k),
        );
        try checkError(state, rc);
    }

    /// TODO: convert to Error union
    fn checkError(state: *const State, rc: c_int) Error!void {
        if (rc != c.LUA_OK) {
            printLuaError(state.inner);
            return Error.UnknownError;
        }
    }

    ///Pushes onto the stack the value `t[k]`, where t is the value at the given index.
    ///As in Lua, this function may trigger a metamethod for the "index" event (see §2.4).
    //Returns the type of the pushed value.
    pub fn getField(state: *const State, idx: isize, field: [:0]const u8) Type {
        return @enumFromInt(c.lua_getfield(state.inner, @intCast(idx), field));
    }

    pub fn isBoolean(state: *const State, idx: isize) bool {
        if (c.lua_isboolean(state.inner, idx) == 1) return true;
        return false;
    }

    /// Returns the type of the value in the given valid index
    pub fn typeOf(state: *const State, idx: isize) Type {
        return @enumFromInt(c.lua_type(state.inner, idx));
    }

    pub fn toLString(state: *const State, idx: isize) []const u8 {
        var len: usize = 0;
        const ptr = c.lua_tolstring(state.inner, @intCast(idx), &len);
        var slice: []const u8 = undefined;
        slice.ptr = ptr;
        slice.len = len;
        return slice;
    }

    pub fn toUserdata(self: *const State, index: isize) ?*anyopaque {
        return c.lua_touserdata(self.inner, @intCast(index));
    }

    /// Pops a value from the stack and sets it as the new value of global name.
    pub fn setGlobal(self: *const State, name: [:0]const u8) void {
        c.lua_setglobal(self.inner, name);
    }

    /// Pushes a nil value onto the stack.
    pub fn pushNil(self: *const State) void {
        c.lua_pushnil(self.inner);
    }

    pub fn pushBoolean(self: *const State, b: bool) void {
        c.lua_pushboolean(self.inner, @intFromBool(b));
    }

    pub fn getTop(self: *const State) isize {
        return @intCast(c.lua_gettop(self.inner));
    }

    ///Pops n elements from the stack.
    pub fn pop(self: *const State, n: isize) void {
        c.lua_pop(self.inner, @as(c_int, @intCast(n)));
    }

    /// Removes the element at the given valid index,
    /// shifting down the elements above this index to fill the gap.
    /// This function cannot be called with a pseudo-index, because a pseudo-index is not an actual stack position.
    pub fn remove(self: *const State, index: isize) void {
        c.lua_remove(self.inner, index);
    }
};

fn alloc(
    maybe_ud: ?*anyopaque,
    maybe_ptr: ?*anyopaque,
    osize: usize,
    nsize: usize,
) callconv(.c) ?*anyopaque {
    const gpa: *Allocator = @ptrCast(@alignCast(maybe_ud));

    if (nsize == 0) {
        if (maybe_ptr) |ptr| {
            var slice: []u8 = undefined;
            slice.ptr = @ptrCast(ptr);
            slice.len = osize;

            gpa.free(slice);
        }
    } else if (maybe_ptr) |ptr| {
        var slice: []u8 = undefined;
        slice.ptr = @ptrCast(ptr);
        slice.len = osize;

        const new_slice = gpa.realloc(slice, nsize) catch return null;
        return @ptrCast(new_slice.ptr);
    } else {
        const slice = gpa.alloc(u8, nsize) catch return null;
        @memset(slice, 0);
        return @ptrCast(slice.ptr);
    }

    return null;
}

pub const Type = enum(c_int) {
    none = c.LUA_TNONE,
    nil = c.LUA_TNIL,
    boolean = c.LUA_TBOOLEAN,
    light_userdata = c.LUA_TLIGHTUSERDATA,
    number = c.LUA_TNUMBER,
    string = c.LUA_TSTRING,
    table = c.LUA_TTABLE,
    function = c.LUA_TFUNCTION,
    userdata = c.LUA_TUSERDATA,
    thread = c.LUA_TTHREAD,
};

pub const Op = enum(c_int) {
    /// performs addition (+)
    add = c.LUA_OPADD,
    sub = c.LUA_OPSUB,
    mul = c.LUA_OPMUL,
    div = c.LUA_OPDIV,
    idiv = c.LUA_OPIDIV,
    mod = c.LUA_OPMOD,
    pow = c.LUA_OPPOW,
    /// performs mathematical negation (unary -)
    unm = c.LUA_OPUNM,
    // TODO: add more ops
};

pub const CFunction = *const fn (?*LuaState) callconv(.c) c_int;
pub const KFunction = ?*const fn (state: ?*LuaState, status: isize, ctx: isize) callconv(.c) isize;
