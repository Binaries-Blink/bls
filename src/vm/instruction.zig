const std = @import("std");
const Operator = @import("blast").Operator;
const Chunk = @import("chunk.zig").Chunk;

pub const Opcode = enum(u8) {
    /// load a constant
    LOADC,
    /// load a function
    LOADF,
    // load & store
    /// load integer literal directly into a register
    LOADI,
    /// load value from one register into another
    LOADR,
    /// load value from heap memory
    LOADM,
    /// write value to heap memory
    STOREM,
    /// log a certain register to be used for the next function call
    ARG,

    // arithmetic
    ADD, SUB,
    MUL, DIV, MOD,
    NEG, POS,

    // bitwise
    AND, OR, XOR,
    NOT, SHL, SHR,

    // comparison
    EQ, NE,
    GT, GE,
    LT, LE,

    // control flow
    JMP,
    JE,
    JNE,
    RET,
    RET_VOID,
    CALL,

    // heap memory
    ALLOC, FREE,

    // casting
    ITOF,
    FTOI,
};

pub fn opToCode(op: Operator) ?Opcode {
    return switch (op) {
        .Add => .ADD,
        .Sub => .SUB,
        .Mul => .MUL,
        .Div => .DIV,
        .Mod => .MOD,

        .Eq => .EQ,
        .Neq => .NE,
        .Gt => .GT,
        .Ge => .GE,
        .Lt => .LT,
        .Le => .LE,

        .BitAnd => .AND,
        .BitOr => .OR,
        .BitXor => .XOR,
        .BitNot => .NOT,
        .Lshift => .SHL,
        .Rshift => .SHR,

        else => null,
    };
}

pub fn prefixOpToCode(op: Operator) ?Opcode {
    return switch (op) {
        .Add => .POS,
        .Sub => .NEG,
        .BitNot => .NOT,
        else => null,
    };
}

/// register instruction
///
/// ex. ADD r1, r2, r3
pub const RInst = packed struct(u32) {
    code: u8,
    dst : u6,
    src1: u6,
    src2: u6,
    _   : u6 = 0,

    pub fn encode(self: RInst) u32 {
        return @bitCast(RInst {
            .code = self.code,
            .dst = self.dst,
            .src1 = self.src1,
            .src2 = self.src2,
        });
    }
};

/// immediate instruction
///
/// ex. LOAD_IMM r1, 42
pub const IInst = packed struct(u32) {
    code: u8,
    dst : u6,
    src : u6,
    imm : i12,

    pub fn encode(self: IInst) u32 {
        return @bitCast(IInst {
            .code = self.code,
            .dst = self.dst,
            .src = self.src,
            .imm = self.imm,
        });
    }
};

/// Jump instructions
///
/// ex. JMP +14
pub const JInst = packed struct(u32) {
    code  : u8,
    /// meanings based on code:
    /// ```txt
    /// JMP      -> None, it is unused
    /// JE / JNE -> will jump if value in reg is true / false
    /// RET      -> register contains the value to return
    /// CALL     -> value returned by call is stored in reg
    /// LOAD_FN  -> loads a reference to the function into reg
    /// ```
    reg   : u6,
    offset: i18,

    pub fn encode(self: JInst) u32 {
        return @bitCast(JInst {
            .code = self.code,
            .reg = self.reg,
            .offset = self.offset,
        });
    }
};

pub const Instruction = union(enum) {
    reg: RInst,
    imm: IInst,
    jmp: JInst,

    pub fn decode(encoded: u32) Instruction {
        const op: Opcode = @enumFromInt(encoded & 0xff);

        return switch (op) {
            .ADD, .SUB, .MUL, .DIV, .MOD,
            .AND, .OR, .XOR,
            .SHL, .SHR,
            .EQ, .NE, .GT, .GE, .LT, .LE,
            .NEG, .NOT, .POS,
            .LOADR, .FREE => Instruction { .reg = @bitCast(encoded) },

            .LOADI, .LOADM, .STOREM,
            .ITOF, .FTOI,
            .ARG, .ALLOC => Instruction { .imm = @bitCast(encoded) },

            .LOADC, .JMP, .JE, .JNE,
            .LOADF, .RET,
            .CALL,
            .RET_VOID => Instruction { .jmp = @bitCast(encoded) },
        };
    }
};


pub fn writeInstruction(encoded: u32, writer: *std.Io.Writer, container: *const Chunk) !void {
    const op: Opcode = @enumFromInt(encoded & 0xff);
    try writer.print("{s: <7} ", .{@tagName(op)});
    switch (op) {
        .ADD, .SUB, .MUL, .DIV, .MOD,
        .AND, .OR, .XOR,
        .SHL, .SHR,
        .EQ, .NE, .GT, .GE, .LT, .LE,
        .NEG, .NOT, .POS,
        .LOADR, .FREE => {
            const inst: RInst = @bitCast(encoded);
            try writer.print("r{d} r{d} r{d}", .{inst.dst, inst.src1, inst.src2});
        },
        .LOADI, .LOADM, .STOREM,
        .ITOF, .FTOI, .ARG, .ALLOC => {
            const inst: IInst = @bitCast(encoded);
            try writer.print("r{d} r{d} #{d}", .{inst.dst, inst.src, inst.imm});
        },
        .JMP, .JE, .JNE,
        .LOADF, .LOADC, .RET => {
            const inst: JInst = @bitCast(encoded);
            try writer.print("r{d} #{d}", .{inst.reg, inst.offset});
        },
        .CALL => {
            const inst: JInst = @bitCast(encoded);
            try writer.print("r{d} {s}", .{
                inst.reg,
                container.functions.items[@intCast(inst.offset)].name
            });
        },
        .RET_VOID => {
            try writer.print("RET_VOID", .{});
        },
    }
}