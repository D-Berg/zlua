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
const assert = std.debug.assert;

pub const LuaState = c.lua_State;

pub const Error = error{
    NewStateError,
    /// a runtime error.
    Run,
    /// memory allocation error. For such errors, Lua does not call the message handler.
    Mem,
    /// stack overflow while running the message handler due to another stack overflow.
    /// More often than not, this error is the result of some other error while running a message handler.
    /// An error in a message handler will call the handler again, which will generate the error again,
    /// and so on, until this loop exhausts the stack and cause this error.
    Err,
    /// syntax error during precompilation or format error in a binary chunk.
    Syntax,
    /// the thread (coroutine) yields.
    Yield,
    ///  a file-related error; e.g., it cannot open or read the file.
    File,

    Unknown,
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
    pub fn new(self: *State, seed: u32) Error!void {
        if (self.gpa) |*gpa| {
            if (c.lua_newstate(alloc, gpa, seed)) |state| {
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
    pub fn setField(self: *const State, idx: i32, k: [:0]const u8) void {
        c.lua_setfield(self.inner, idx, k);
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

    pub fn pushInteger(self: *const State, n: c.lua_Integer) void {
        c.lua_pushinteger(self.inner, n);
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

    pub fn upvalueIndex(self: *const State, n: u32) i32 {
        _ = self;
        assert(n >= 1 and n <= 256);
        return c.lua_upvalueindex(@as(c_int, @intCast(n)));
    }
    /// Loads a string as a Lua chunk. This function uses lua_load to load the chunk in the zero-terminated string s.
    /// This function returns the same results as lua_load.
    /// Also as lua_load, this function only loads the chunk; it does not run it.
    pub fn loadString(state: *const State, string: [:0]const u8) Error!void {
        try checkError(c.luaL_loadstring(state.inner, string));
    }

    pub fn loadBufferx(self: *const State, buff: []const u8, name: [:0]const u8, mode: [*c]const u8) Error!void {
        try checkError(c.luaL_loadbufferx(self.inner, buff.ptr, buff.len, name, mode));
    }

    pub fn loadBuffer(self: *const State, buff: []const u8, name: [:0]const u8) Error!void {
        try self.loadBufferx(buff, name, null);
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
    pub fn pcall(state: *const State, nargs: u32, nresults: i32, msgh: isize) !void {
        try state.pcallk(nargs, nresults, msgh, 0, null);
    }

    /// This function behaves exactly like lua_pcall, except that it allows the called function to yield (see §4.5).
    pub fn pcallk(state: *const State, nargs: u32, nresults: i32, msgh: isize, ctx: isize, k: KFunction) !void {
        try checkError(c.lua_pcallk(
            state.inner,
            @as(c_int, @intCast(nargs)),
            @as(c_int, @intCast(nresults)),
            @as(c_int, @intCast(msgh)),
            ctx,
            @ptrCast(k),
        ));
    }

    /// TODO: convert to Error union
    fn checkError(rc: c_int) Error!void {
        switch (rc) {
            c.LUA_OK => return,
            c.LUA_ERRRUN => return Error.Run,
            c.LUA_ERRMEM => return Error.Mem,
            c.LUA_ERRERR => return Error.Err,
            c.LUA_ERRSYNTAX => return Error.Syntax,
            c.LUA_YIELD => return Error.Yield,
            c.LUA_ERRFILE => return Error.File,
            else => return Error.Unknown,
        }
    }

    ///Pushes onto the stack the value `t[k]`, where t is the value at the given index.
    ///As in Lua, this function may trigger a metamethod for the "index" event (see §2.4).
    //Returns the type of the pushed value.
    pub fn getField(state: *const State, idx: i32, field: [:0]const u8) Type {
        return @enumFromInt(c.lua_getfield(state.inner, idx, field));
    }

    pub fn isBoolean(state: *const State, idx: i32) bool {
        if (c.lua_isboolean(state.inner, idx) == 1) return true;
        return false;
    }

    /// Returns the type of the value in the given valid index
    pub fn typeOf(state: *const State, idx: i32) Type {
        return @enumFromInt(c.lua_type(state.inner, idx));
    }

    pub fn toLString(state: *const State, idx: i32) []const u8 {
        var len: usize = 0;
        const ptr = c.lua_tolstring(state.inner, idx, &len);
        var slice: []const u8 = undefined;
        slice.ptr = ptr;
        slice.len = len;
        return slice;
    }

    pub fn rawLen(self: *const State, idx: i32) usize {
        return c.lua_rawlen(self.inner, idx);
    }

    pub fn rawGetI(self: *const State, idx: i32, n: isize) Type {
        return @enumFromInt(c.lua_rawgeti(self.inner, idx, n));
    }

    pub fn toUserdata(self: *const State, idx: i32) ?*anyopaque {
        return c.lua_touserdata(self.inner, idx);
    }

    pub fn toBoolean(self: *const State, idx: i32) bool {
        if (c.lua_toboolean(self.inner, idx) == 0) return false;
        return true;
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

    pub fn getTop(self: *const State) i32 {
        return c.lua_gettop(self.inner);
    }

    ///Pops n elements from the stack.
    pub fn pop(self: *const State, n: i32) void {
        c.lua_pop(self.inner, n);
    }

    /// Removes the element at the given valid index,
    /// shifting down the elements above this index to fill the gap.
    /// This function cannot be called with a pseudo-index, because a pseudo-index is not an actual stack position.
    pub fn remove(self: *const State, idx: i32) void {
        c.lua_remove(self.inner, idx);
    }
};

const alignment = @alignOf(std.c.max_align_t);
fn alloc(
    maybe_ud: ?*anyopaque,
    ptr: ?*anyopaque,
    osize: usize,
    nsize: usize,
) callconv(.c) ?*align(alignment) anyopaque {
    const gpa: *Allocator = @ptrCast(@alignCast(maybe_ud));

    // https://github.com/natecraddock/ziglua/blob/188ba36e8054bcf1929117fb7c96d9f939296059/src/lib.zig#L599C5-L628C6
    // ziglua MIT Copyright (c) 2022 Nathan Craddock
    if (@as(?[*]align(alignment) u8, @ptrCast(@alignCast(ptr)))) |prev_ptr| {
        const prev_slice = prev_ptr[0..osize];

        // when nsize is zero the allocator must behave like free and return null
        if (nsize == 0) {
            gpa.free(prev_slice);
            return null;
        }

        // when nsize is not zero the allocator must behave like realloc
        const new_ptr = gpa.realloc(prev_slice, nsize) catch return null;
        return new_ptr.ptr;
    } else if (nsize == 0) {
        return null;
    } else { // ptr is null, allocate a new block of memory
        const new_ptr = gpa.alignedAlloc(u8, .fromByteUnits(alignment), nsize) catch return null;
        return new_ptr.ptr;
    }
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
